import SwiftUI

enum WidgetRegistry {
    static let all: [WidgetDescriptor] = [
        WidgetDescriptor(
            id: "claude_status",
            displayName: "Claude 状态",
            iconName: "brain.head.profile",
            viewBuilder: { env, align in AnyView(ClaudeStatusWidget(status: env.claudeStatus.status, titleAlignment: align)) }
        ),
        WidgetDescriptor(
            id: "calendar",
            displayName: "日历",
            iconName: "calendar",
            viewBuilder: { _, align in AnyView(CalendarWidget(titleAlignment: align)) }
        ),
        WidgetDescriptor(
            id: "timer",
            displayName: "计时器",
            iconName: "timer",
            viewBuilder: { env, align in AnyView(TimerWidget(timerModel: env.timerModel, titleAlignment: align)) }
        ),
        WidgetDescriptor(
            id: "system_stats",
            displayName: "系统监控",
            iconName: "cpu",
            viewBuilder: { env, align in AnyView(SystemStatsWidget(systemStats: env.systemStats, titleAlignment: align)) }
        ),
        WidgetDescriptor(
            id: "weather",
            displayName: "天气",
            iconName: "cloud.sun.fill",
            viewBuilder: { env, align in AnyView(WeatherWidget(weather: env.weather, titleAlignment: align)) }
        ),
        WidgetDescriptor(
            id: "battery",
            displayName: "电池",
            iconName: "battery.75",
            viewBuilder: { env, align in AnyView(BatteryWidget(battery: env.battery, titleAlignment: align)) }
        ),
        WidgetDescriptor(
            id: "music",
            displayName: "音乐",
            iconName: "music.note",
            viewBuilder: { env, align in AnyView(MusicWidget(music: env.music, titleAlignment: align)) }
        ),
        WidgetDescriptor(
            id: "git_status",
            displayName: "Git",
            iconName: "arrow.triangle.branch",
            viewBuilder: { env, align in AnyView(GitStatusWidget(git: env.gitStatus, titleAlignment: align)) }
        ),
        WidgetDescriptor(
            id: "port_monitor",
            displayName: "端口监控",
            iconName: "network",
            viewBuilder: { env, align in AnyView(PortMonitorWidget(portMonitor: env.portMonitor, titleAlignment: align)) }
        ),
        WidgetDescriptor(
            id: "docker",
            displayName: "Docker",
            iconName: "shippingbox.fill",
            viewBuilder: { env, align in AnyView(DockerWidget(docker: env.docker, titleAlignment: align)) }
        ),
        WidgetDescriptor(
            id: "clipboard",
            displayName: "剪贴板",
            iconName: "doc.on.clipboard",
            viewBuilder: { env, align in AnyView(ClipboardWidget(clipboard: env.clipboard, titleAlignment: align)) }
        ),
        WidgetDescriptor(
            id: "pomodoro",
            displayName: "番茄钟",
            iconName: "leaf.fill",
            viewBuilder: { env, align in AnyView(PomodoroWidget(pomodoro: env.pomodoro, titleAlignment: align)) }
        ),
        WidgetDescriptor(
            id: "volume",
            displayName: "音量",
            iconName: "speaker.wave.2.fill",
            viewBuilder: { env, align in AnyView(VolumeWidget(volumeProvider: env.volume, titleAlignment: align)) }
        ),
        WidgetDescriptor(
            id: "quick_launch",
            displayName: "快捷启动",
            iconName: "square.grid.2x2",
            viewBuilder: { _, align in AnyView(QuickLaunchWidget(titleAlignment: align)) }
        ),
    ]

    static func descriptor(for id: String) -> WidgetDescriptor? {
        all.first { $0.id == id }
    }
}
