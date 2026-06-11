import SwiftUI
import Combine

// Claude Code 状态发生关键跃迁时发出的一次性事件，供通知 / notch 动画消费。
enum ClaudeEvent {
    case completed(elapsed: TimeInterval)  // 活跃态 → 等待你（任务交回）
    case needsPermission                   // 需要切回授权
    case failed                            // 任务出错
}

// 单个 Claude Code 会话的状态快照，由 hook 写入 sessions/<id>.json。
struct ClaudeSession: Identifiable {
    let id: String
    var status: ClaudeStatus
    var tool: String?
    var detail: String?
    var projectName: String?   // cwd 的最后一段
    var pid: Int32?
    var transcriptPath: String?
    var toolStartedAt: Date?
    var updatedAt: Date?
    var hookResult: String?    // Stop payload 自带的最后回复（last_assistant_message）
    var lastResult: String?    // 完成时展示的最后回复摘要
    var contextPercent: Int?   // 上下文窗口用量百分比
}

@MainActor
final class ClaudeStatusProvider: ObservableObject {
    // 聚合后的主导会话状态（收起态与单会话 UI 直接使用，多会话时取最需要关注的那个）。
    @Published private(set) var status: ClaudeStatus = .idle
    // 当前工具与目标，由 hook 写入（如 Edit / App.swift）。
    @Published private(set) var tool: String?
    @Published private(set) var detail: String?
    // 当前工具已运行秒数，由本地计时器每秒推进，不依赖文件轮询。
    @Published private(set) var toolElapsed: Int = 0
    // 全部存活会话，按关注优先级排序（主导会话在最前）。
    @Published private(set) var sessions: [ClaudeSession] = []

    // 跃迁事件流：completed / needsPermission / failed。
    let events = PassthroughSubject<ClaudeEvent, Never>()

    nonisolated static let sessionsDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude-code-notch/sessions")
    private var pollTimer: Timer?
    private var tickTimer: Timer?

    // 每会话的跃迁基线 / 任务起点 / 完成摘要，会话消失时一并清理。
    private var prevStatus: [String: ClaudeStatus] = [:]
    private var taskStartedAt: [String: Date] = [:]
    private var lastResults: [String: String] = [:]
    private var contextPercents: [String: Int] = [:]
    private var dominantToolStartedAt: Date?

    init() {
        refresh()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        guard status == .running, let start = dominantToolStartedAt else {
            if toolElapsed != 0 { toolElapsed = 0 }
            return
        }
        toolElapsed = max(0, Int(Date().timeIntervalSince(start)))
    }

    private func refresh() {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: Self.sessionsDir, includingPropertiesForKeys: nil)) ?? []
        var loaded: [ClaudeSession] = []
        for url in files where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  let payload = try? JSONDecoder().decode(SessionPayload.self, from: data) else { continue }
            // claude 进程已退出（崩溃/被杀，没走到 SessionEnd）或状态过期 → 清掉孤儿会话文件。
            if payload.isStale || !payload.processAlive {
                try? fm.removeItem(at: url)
                continue
            }
            loaded.append(payload.session(id: url.deletingPathExtension().lastPathComponent))
        }
        apply(sessions: loaded)
    }

    private func apply(sessions loaded: [ClaudeSession]) {
        // 每会话独立判定跃迁；首次见到的会话只建基线不发事件，避免误报历史状态。
        for session in loaded {
            guard let previous = prevStatus[session.id] else {
                prevStatus[session.id] = session.status
                if session.status.isActive { taskStartedAt[session.id] = Date() }
                continue
            }
            if session.status.isActive && !previous.isActive {
                taskStartedAt[session.id] = Date()
            }
            switch session.status {
            case .waiting where previous.isActive:
                handleCompletion(of: session)
            case .allow where previous != .allow:
                events.send(.needsPermission)
            case .error where previous != .error:
                events.send(.failed)
            default:
                break
            }
            prevStatus[session.id] = session.status
        }

        // 清理已消失会话的跟踪状态。
        let liveIDs = Set(loaded.map(\.id))
        prevStatus = prevStatus.filter { liveIDs.contains($0.key) }
        taskStartedAt = taskStartedAt.filter { liveIDs.contains($0.key) }
        lastResults = lastResults.filter { liveIDs.contains($0.key) }
        contextPercents = contextPercents.filter { liveIDs.contains($0.key) }

        // 补充 transcript 提取的结果摘要 / 上下文用量，再按关注优先级排序。
        var enriched = loaded.map { session -> ClaudeSession in
            var s = session
            s.lastResult = lastResults[s.id]
            s.contextPercent = contextPercents[s.id]
            return s
        }
        enriched.sort {
            if $0.status.priority != $1.status.priority {
                return $0.status.priority > $1.status.priority
            }
            return ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast)
        }
        sessions = enriched

        // 主导会话决定收起态显示内容；无会话 = Claude Code 未运行。
        if let top = enriched.first {
            status = top.status
            tool = top.tool
            detail = top.detail
            dominantToolStartedAt = top.toolStartedAt
        } else {
            status = .disconnected
            tool = nil
            detail = nil
            dominantToolStartedAt = nil
        }
        if status != .running {
            dominantToolStartedAt = nil
            toolElapsed = 0
        }
    }

    // 任务交回：解析 transcript 提取 API 错误 / 上下文用量，结合 hook 自带的最后回复，
    // 再发完成或失败事件。
    private func handleCompletion(of session: ClaudeSession) {
        let elapsed = taskStartedAt[session.id].map { Date().timeIntervalSince($0) } ?? 0
        var resultText = session.hookResult

        if let path = session.transcriptPath {
            let parsed = TranscriptParser.parse(path: path, sessionId: session.id)
            if let used = parsed.contextUsedTokens {
                // 窗口大小 hook 拿不到：用量水位/模型名推断 1M，菜单开关可强制按 1M 算。
                let oneM = parsed.contextInferred1M
                    || UserDefaults.standard.bool(forKey: Self.context1MKey)
                let limit = oneM ? 1_000_000.0 : 200_000.0
                contextPercents[session.id] = min(100, Int((Double(used) / limit * 100).rounded()))
            }
            // Claude Code 把 API 错误（限流/计费等）伪装成普通 Stop，这里识别后按失败处理。
            if let apiError = parsed.apiError {
                prevStatus[session.id] = .error
                lastResults[session.id] = "API 错误：\(apiError)"
                events.send(.failed)
                return
            }
            if resultText == nil {
                resultText = parsed.lastAssistantText
            }
        }
        if let resultText {
            lastResults[session.id] = Self.cleanResult(resultText)
        }
        events.send(.completed(elapsed: elapsed))
    }

    nonisolated static let context1MKey = "contextWindow1M"

    // 摘要清洗：去掉行首 markdown 符号（#、>、列表点），压缩空白，截到适合卡片的长度。
    private nonisolated static func cleanResult(_ text: String) -> String {
        let cleaned = text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { line -> String in
                var s = Substring(line.trimmingCharacters(in: .whitespaces))
                while let first = s.first, "#>*-".contains(first) { s = s.dropFirst() }
                return s.trimmingCharacters(in: .whitespaces)
            }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        guard cleaned.count > 160 else { return cleaned }
        return String(cleaned.prefix(159)) + "…"
    }
}

private struct SessionPayload: Decodable {
    let status: String
    let tool: String?
    let detail: String?
    let updatedAt: Date?
    let toolStartedAt: Date?
    let sessionId: String?
    let cwd: String?
    let pid: Int32?
    let transcriptPath: String?
    let result: String?

    private enum CodingKeys: String, CodingKey {
        case status, tool, detail, updatedAt, toolStartedAt
        case sessionId, cwd, pid, transcriptPath, result
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decode(String.self, forKey: .status)
        tool = try container.decodeIfPresent(String.self, forKey: .tool)
        detail = try container.decodeIfPresent(String.self, forKey: .detail)
        updatedAt = Self.parseDate(try container.decodeIfPresent(String.self, forKey: .updatedAt))
        toolStartedAt = Self.parseDate(try container.decodeIfPresent(String.self, forKey: .toolStartedAt))
        sessionId = try container.decodeIfPresent(String.self, forKey: .sessionId)
        cwd = try container.decodeIfPresent(String.self, forKey: .cwd)
        pid = try container.decodeIfPresent(Int32.self, forKey: .pid)
        transcriptPath = try container.decodeIfPresent(String.self, forKey: .transcriptPath)
        result = try container.decodeIfPresent(String.self, forKey: .result)
    }

    private static func parseDate(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        return ISO8601DateFormatter().date(from: raw)
    }

    var isStale: Bool {
        guard let updatedAt else { return true }
        // 防止隔很久后仍显示上一次 Claude Code 会话的 Running/Thinking。
        return Date().timeIntervalSince(updatedAt) > 30 * 60
    }

    // hook 记录了 claude 进程 PID 时做存活检测；EPERM 也算活着（无权限但进程存在）。
    var processAlive: Bool {
        guard let pid, pid > 0 else { return true }
        if kill(pid, 0) == 0 { return true }
        return errno == EPERM
    }

    func session(id: String) -> ClaudeSession {
        ClaudeSession(
            id: sessionId ?? id,
            status: ClaudeStatus(rawValue: status) ?? .idle,
            tool: tool,
            detail: detail,
            projectName: cwd.flatMap { URL(fileURLWithPath: $0).lastPathComponent },
            pid: pid,
            transcriptPath: transcriptPath,
            toolStartedAt: toolStartedAt,
            updatedAt: updatedAt,
            hookResult: result
        )
    }
}

enum ClaudeStatus: String {
    case disconnected
    case idle
    case thinking
    case running
    case waiting
    case allow
    case error

    // 活跃态：Claude 正在干活，是判定“任务完成”跃迁的前提。
    var isActive: Bool {
        switch self {
        case .thinking, .running: true
        default: false
        }
    }

    // 多会话聚合时的关注优先级：要授权的最优先，其次出错，再次正在干活。
    var priority: Int {
        switch self {
        case .allow: 6
        case .error: 5
        case .running: 4
        case .thinking: 3
        case .waiting: 2
        case .idle: 1
        case .disconnected: 0
        }
    }

    var displayText: String {
        switch self {
        case .disconnected: "未连接"
        case .idle: "Idle"
        case .thinking: "Thinking"
        case .running: "Running"
        case .waiting: "Waiting"
        case .allow: "Needs Allow"
        case .error: "Error"
        }
    }

    var description: String {
        switch self {
        case .disconnected: "Claude Code 未运行或无最近状态"
        case .idle: "Claude Code 当前空闲"
        case .thinking: "正在思考或生成方案"
        case .running: "正在执行工具或命令"
        case .waiting: "等待你继续输入"
        case .allow: "需要切回 Claude Code 授权"
        case .error: "任务遇到错误"
        }
    }

    var actionText: String {
        switch self {
        case .disconnected: "启动 Claude Code 后自动更新"
        case .idle: "可以开始新任务"
        case .thinking: "保持当前窗口即可"
        case .running: "等待执行完成"
        case .waiting: "切回输入下一步"
        case .allow: "切回并点击 Allow"
        case .error: "切回查看错误"
        }
    }

    var symbolName: String {
        switch self {
        case .disconnected: "powerplug.fill"
        case .idle: "moon.zzz.fill"
        case .thinking: "brain.head.profile"
        case .running: "terminal.fill"
        case .waiting: "text.bubble.fill"
        case .allow: "hand.raised.fill"
        case .error: "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch self {
        case .disconnected: .white.opacity(0.42)
        case .idle: .white.opacity(0.64)
        case .thinking: .purple
        case .running: .green
        case .waiting: .yellow
        case .allow: .orange
        case .error: .red
        }
    }

    var isAnimated: Bool {
        switch self {
        case .thinking, .running, .allow:
            true
        case .disconnected, .idle, .waiting, .error:
            false
        }
    }
}
