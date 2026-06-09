import SwiftUI
import Combine

// Claude Code 状态发生关键跃迁时发出的一次性事件，供通知 / notch 动画消费。
enum ClaudeEvent {
    case completed(elapsed: TimeInterval)  // 活跃态 → 等待你（任务交回）
    case needsPermission                   // 需要切回授权
    case failed                            // 任务出错
}

@MainActor
final class ClaudeStatusProvider: ObservableObject {
    @Published private(set) var status: ClaudeStatus = .idle
    // 当前工具与目标，由 hook 写入（如 Edit / App.swift）。
    @Published private(set) var tool: String?
    @Published private(set) var detail: String?
    // 当前工具已运行秒数，由本地计时器每秒推进，不依赖文件轮询。
    @Published private(set) var toolElapsed: Int = 0

    // 跃迁事件流：completed / needsPermission / failed。
    let events = PassthroughSubject<ClaudeEvent, Never>()

    private let statusURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude-code-notch/status.json")
    private var pollTimer: Timer?
    private var tickTimer: Timer?

    private var toolStartedAt: Date?
    private var taskStartedAt: Date?
    // 首次读取只用于建立基线，不触发事件，避免启动时误报历史状态。
    private var didInitialRead = false

    init() {
        refresh()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        guard status == .running, let start = toolStartedAt else {
            if toolElapsed != 0 { toolElapsed = 0 }
            return
        }
        toolElapsed = max(0, Int(Date().timeIntervalSince(start)))
    }

    private func refresh() {
        // 状态由 Claude Code hooks 写入本地 JSON；文件缺失或过期时视为未连接。
        guard let data = try? Data(contentsOf: statusURL),
              let payload = try? JSONDecoder().decode(StatusPayload.self, from: data),
              !payload.isStale else {
            apply(status: .disconnected, tool: nil, detail: nil, startedAt: nil)
            return
        }
        let newStatus = ClaudeStatus(rawValue: payload.status) ?? .idle
        apply(status: newStatus, tool: payload.tool, detail: payload.detail, startedAt: payload.toolStartedAt)
    }

    private func apply(status newStatus: ClaudeStatus, tool newTool: String?, detail newDetail: String?, startedAt: Date?) {
        let previous = status
        let wasActive = previous.isActive
        let isActive = newStatus.isActive

        tool = newTool
        detail = newDetail
        toolStartedAt = startedAt

        // 进入活跃态（且此前不活跃）记一次任务起点，用于完成时报告整任务用时。
        if isActive && !wasActive {
            taskStartedAt = Date()
        }

        if didInitialRead {
            switch newStatus {
            case .waiting where wasActive:
                let elapsed = taskStartedAt.map { Date().timeIntervalSince($0) } ?? 0
                events.send(.completed(elapsed: elapsed))
            case .allow where previous != .allow:
                events.send(.needsPermission)
            case .error where previous != .error:
                events.send(.failed)
            default:
                break
            }
        }
        didInitialRead = true

        status = newStatus
        if newStatus != .running {
            toolStartedAt = nil
            toolElapsed = 0
        }
    }
}

private struct StatusPayload: Decodable {
    let status: String
    let tool: String?
    let detail: String?
    let updatedAt: Date?
    let toolStartedAt: Date?

    private enum CodingKeys: String, CodingKey {
        case status
        case tool
        case detail
        case updatedAt
        case toolStartedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decode(String.self, forKey: .status)
        tool = try container.decodeIfPresent(String.self, forKey: .tool)
        detail = try container.decodeIfPresent(String.self, forKey: .detail)
        updatedAt = Self.parseDate(try container.decodeIfPresent(String.self, forKey: .updatedAt))
        toolStartedAt = Self.parseDate(try container.decodeIfPresent(String.self, forKey: .toolStartedAt))
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
