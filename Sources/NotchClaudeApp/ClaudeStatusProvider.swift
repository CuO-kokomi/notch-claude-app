import SwiftUI

@MainActor
final class ClaudeStatusProvider: ObservableObject {
    @Published private(set) var status: ClaudeStatus = .idle

    private let statusURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude-code-notch/status.json")
    private var timer: Timer?

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    private func refresh() {
        // 状态由 Claude Code hooks 写入本地 JSON；文件缺失或过期时视为未连接。
        guard let data = try? Data(contentsOf: statusURL),
              let payload = try? JSONDecoder().decode(StatusPayload.self, from: data),
              !payload.isStale else {
            status = .disconnected
            return
        }
        status = ClaudeStatus(rawValue: payload.status) ?? .idle
    }
}

private struct StatusPayload: Decodable {
    let status: String
    let updatedAt: Date?

    private enum CodingKeys: String, CodingKey {
        case status
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decode(String.self, forKey: .status)
        if let rawUpdatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) {
            updatedAt = ISO8601DateFormatter().date(from: rawUpdatedAt)
        } else {
            updatedAt = nil
        }
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
