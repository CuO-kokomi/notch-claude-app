import AppKit
import Combine
import UserNotifications

// 监听 Claude 状态跃迁，在任务完成 / 需授权 / 出错时发系统通知 + 声音。
// 开关以 UserDefaults 为唯一真相，和右键菜单共享，无需相互持有引用。
@MainActor
final class NotificationManager {
    nonisolated static let notifyKey = "notifyEnabled"
    nonisolated static let soundKey = "soundEnabled"

    // 默认开。在 app 启动尽早调用，确保菜单勾选与本管理器读到一致的默认值。
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [notifyKey: true, soundKey: true])
    }

    private var cancellable: AnyCancellable?

    private var notifyEnabled: Bool { UserDefaults.standard.bool(forKey: Self.notifyKey) }
    private var soundEnabled: Bool { UserDefaults.standard.bool(forKey: Self.soundKey) }

    // UNUserNotification 需要打包成 .app 且有 bundle id；从裸二进制(dev)运行时降级为只放声音。
    private var notificationsAvailable: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app"
    }

    func observe(_ provider: ClaudeStatusProvider) {
        cancellable = provider.events.sink { [weak self] event in
            self?.handle(event)
        }
    }

    // 刘海可直接审批的权限请求：通知带上工具与命令摘要。
    func notifyPermissionRequest(_ request: PermissionRequest) {
        let summary = request.detail.map { "\(request.toolName) · \($0)" } ?? request.toolName
        notify(title: "需要授权", body: "\(summary)（可在刘海上直接批准）", sound: "Funk")
    }

    func requestAuthorizationIfNeeded() {
        guard notificationsAvailable else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func handle(_ event: ClaudeEvent) {
        switch event {
        case .completed(let elapsed):
            notify(title: "任务完成", body: "Claude 已交回 · 用时 \(Self.format(elapsed))", sound: "Glass")
        case .needsPermission:
            notify(title: "需要授权", body: "切回 Claude Code 点击 Allow", sound: "Funk")
        case .failed:
            notify(title: "任务出错", body: "切回 Claude Code 查看错误", sound: "Basso")
        }
    }

    private func notify(title: String, body: String, sound: String) {
        if soundEnabled {
            NSSound(named: NSSound.Name(sound))?.play()
        }
        guard notifyEnabled, notificationsAvailable else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        // 声音已用 NSSound 自播，通知本身静音，避免双响。
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private static func format(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        if total < 60 { return "\(total)s" }
        return "\(total / 60)m\(total % 60)s"
    }
}
