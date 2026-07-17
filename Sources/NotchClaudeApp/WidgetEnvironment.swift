import SwiftUI
import Combine

@MainActor
final class WidgetEnvironment: ObservableObject {
    let claudeStatus = ClaudeStatusProvider()
    let notifications = NotificationManager()
    let permissions = PermissionServer()
    let timerModel = TimerViewModel()
    let systemStats = SystemStatsProvider()
    lazy var weather = WeatherProvider()
    lazy var battery = BatteryProvider()
    lazy var music = MusicProvider()
    lazy var gitStatus = GitStatusProvider()
    lazy var portMonitor = PortMonitorProvider()
    lazy var docker = DockerProvider()
    lazy var clipboard = ClipboardProvider()
    lazy var pomodoro = PomodoroProvider()
    lazy var volume = VolumeProvider()
    lazy var sessionHistory = SessionHistoryProvider()

    private var cancellables = Set<AnyCancellable>()

    init() {
        // 完成 / 需授权 / 出错时发通知 + 声音，并请求一次系统通知权限。
        notifications.observe(claudeStatus)
        notifications.requestAuthorizationIfNeeded()
        permissions.onNewRequest = { [weak self] request in
            self?.notifications.notifyPermissionRequest(request)
        }
        claudeStatus.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
        // 会话状态每次刷新都对账一遍待审批请求：终端先回答的请求由状态推进兜底撤卡
        //（新版 Claude Code 不再断开挂起的 hook 连接，等不到对端关闭信号）。
        claudeStatus.$sessions.sink { [weak self] sessions in
            self?.permissions.dismissHandledElsewhere(sessions: sessions)
        }.store(in: &cancellables)
        permissions.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
        timerModel.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
    }

    func warmUp() {
        _ = weather
        _ = battery
        _ = music
        _ = gitStatus
        _ = portMonitor
        _ = docker
        _ = clipboard
        _ = pomodoro
        _ = volume
        _ = sessionHistory
    }
}
