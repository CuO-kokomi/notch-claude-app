import SwiftUI

struct WeatherWidget: View {
    @ObservedObject var weather: WeatherProvider
    var titleAlignment: Alignment = .leading

    var body: some View {
        WidgetCard(title: "天气", titleAlignment: titleAlignment) {
            VStack(spacing: 8) {
                Image(systemName: weather.iconName)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.white.opacity(0.82))
                    .symbolRenderingMode(.hierarchical)
                Text(weather.temperature)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(weather.condition)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.56))
                    .lineLimit(1)
                if !weather.location.isEmpty {
                    Text(weather.location)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.38))
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

struct BatteryWidget: View {
    @ObservedObject var battery: BatteryProvider
    var titleAlignment: Alignment = .leading

    private var batteryIcon: String {
        if battery.isCharging { return "battery.100.bolt" }
        switch battery.percentage {
        case 75...100: return "battery.100"
        case 50..<75: return "battery.75"
        case 25..<50: return "battery.50"
        case 1..<25: return "battery.25"
        default: return "battery.0"
        }
    }

    private var batteryColor: Color {
        if battery.isCharging { return .green }
        if battery.percentage <= 20 { return .red }
        if battery.percentage <= 40 { return .orange }
        return .white.opacity(0.82)
    }

    var body: some View {
        WidgetCard(title: "电池", titleAlignment: titleAlignment) {
            VStack(spacing: 10) {
                Image(systemName: batteryIcon)
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(batteryColor)
                if battery.percentage >= 0 {
                    Text("\(battery.percentage)%")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    if !battery.timeRemaining.isEmpty {
                        Text(battery.timeRemaining)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.56))
                    }
                } else {
                    Text("无电池")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.48))
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

struct MusicWidget: View {
    @ObservedObject var music: MusicProvider
    var titleAlignment: Alignment = .leading

    var body: some View {
        WidgetCard(title: music.playerName.isEmpty ? "音乐" : music.playerName, titleAlignment: titleAlignment) {
            VStack(spacing: 12) {
                if music.trackName.isEmpty {
                    Image(systemName: "music.note")
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(.white.opacity(0.36))
                    Text("未在播放")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.42))
                } else {
                    Text(music.trackName)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(music.artistName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.56))
                        .lineLimit(1)

                    HStack(spacing: 24) {
                        Button(action: { music.previousTrack() }) {
                            Image(systemName: "backward.fill")
                                .font(.system(size: 16))
                        }
                        Button(action: { music.togglePlayPause() }) {
                            Image(systemName: music.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 22))
                        }
                        Button(action: { music.nextTrack() }) {
                            Image(systemName: "forward.fill")
                                .font(.system(size: 16))
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.72))
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

struct GitStatusWidget: View {
    @ObservedObject var git: GitStatusProvider
    var titleAlignment: Alignment = .leading

    var body: some View {
        WidgetCard(title: git.isGitRepo ? git.repoName : "Git", titleAlignment: titleAlignment) {
            if !git.isGitRepo {
                VStack(spacing: 8) {
                    Image(systemName: "questionmark.folder")
                        .font(.system(size: 20))
                        .foregroundStyle(.white.opacity(0.36))
                    Text("无 Git 仓库")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.42))
                    Button(action: { git.pickDirectory() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 11))
                            Text("选择仓库")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundStyle(.white.opacity(0.64))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(.white.opacity(0.08))
                        )
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 13, weight: .semibold))
                        Text(git.branch)
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .lineLimit(1)
                    }
                    .foregroundStyle(.white.opacity(0.82))

                    HStack(spacing: 5) {
                        Circle()
                            .fill(git.uncommittedCount > 0 ? .orange : .green)
                            .frame(width: 8, height: 8)
                        Text(git.uncommittedCount > 0 ? "\(git.uncommittedCount) 未提交" : "工作区干净")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.64))
                    }

                    if !git.lastCommitMessage.isEmpty {
                        Text(git.lastCommitMessage)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.42))
                            .lineLimit(2)
                    }

                    Button(action: { git.pickDirectory() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 10))
                            Text("切换仓库")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundStyle(.white.opacity(0.48))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(.white.opacity(0.06))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct PortMonitorWidget: View {
    @ObservedObject var portMonitor: PortMonitorProvider
    var titleAlignment: Alignment = .leading

    var body: some View {
        WidgetCard(title: "端口", titleAlignment: titleAlignment) {
            let activePorts = portMonitor.ports.filter { $0.isActive }
            if activePorts.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "network")
                        .font(.system(size: 22))
                        .foregroundStyle(.white.opacity(0.36))
                    Text("无活跃端口")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.42))
                }
                .frame(maxWidth: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(activePorts) { port in
                        HStack(spacing: 5) {
                            Circle().fill(.green).frame(width: 6, height: 6)
                            Text(":\(port.port)")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.82))
                            Text(port.process)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.white.opacity(0.48))
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
    }
}

struct DockerWidget: View {
    @ObservedObject var docker: DockerProvider
    var titleAlignment: Alignment = .leading

    var body: some View {
        WidgetCard(title: "Docker", titleAlignment: titleAlignment) {
            if !docker.isDockerRunning {
                VStack(spacing: 6) {
                    Image(systemName: "shippingbox")
                        .font(.system(size: 22))
                        .foregroundStyle(.white.opacity(0.36))
                    Text("Docker 未运行")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.42))
                }
                .frame(maxWidth: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    let running = docker.containers.filter { $0.isRunning }.count
                    HStack(spacing: 5) {
                        Image(systemName: "shippingbox.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.green)
                        Text("\(running) 运行中")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.72))
                    }
                    ForEach(docker.containers.prefix(4)) { container in
                        HStack(spacing: 5) {
                            Circle()
                                .fill(container.isRunning ? .green : .gray)
                                .frame(width: 7, height: 7)
                            Text(container.name)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.64))
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
    }
}

struct ClipboardWidget: View {
    @ObservedObject var clipboard: ClipboardProvider
    var titleAlignment: Alignment = .leading
    @State private var copiedID: UUID?

    var body: some View {
        WidgetCard(title: "剪贴板", titleAlignment: titleAlignment) {
            if clipboard.items.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 22))
                        .foregroundStyle(.white.opacity(0.36))
                    Text("暂无记录")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.42))
                }
                .frame(maxWidth: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(clipboard.items.prefix(5)) { item in
                        Button(action: {
                            clipboard.copyToClipboard(item.text)
                            copiedID = item.id
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                if copiedID == item.id { copiedID = nil }
                            }
                        }) {
                            HStack(spacing: 4) {
                                Text(copiedID == item.id ? "已复制" : item.text.prefix(40).replacingOccurrences(of: "\n", with: " "))
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundStyle(copiedID == item.id ? .green : .white.opacity(0.64))
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.vertical, 3)
                            .padding(.horizontal, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(copiedID == item.id ? .green.opacity(0.1) : .white.opacity(0.05))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

struct PomodoroWidget: View {
    @ObservedObject var pomodoro: PomodoroProvider
    var titleAlignment: Alignment = .leading

    private var phaseColor: Color {
        switch pomodoro.phase {
        case .idle: return .white.opacity(0.56)
        case .work: return .red
        case .shortBreak: return .green
        case .longBreak: return .blue
        }
    }

    var body: some View {
        WidgetCard(title: "番茄钟", titleAlignment: titleAlignment) {
            VStack(spacing: 8) {
                Text(pomodoro.formattedTime)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)

                Text(pomodoro.phase.rawValue)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(phaseColor)

                HStack(spacing: 5) {
                    ForEach(0..<4, id: \.self) { i in
                        Circle()
                            .fill(i < pomodoro.completedPomodoros % 4 ? .red : .white.opacity(0.2))
                            .frame(width: 7, height: 7)
                    }
                }

                HStack(spacing: 14) {
                    Button(action: { pomodoro.isRunning ? pomodoro.pause() : pomodoro.start() }) {
                        Image(systemName: pomodoro.isRunning ? "pause.fill" : "play.fill")
                            .font(.system(size: 13))
                    }
                    Button(action: { pomodoro.skip() }) {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 13))
                    }
                    Button(action: { pomodoro.reset() }) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 13))
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.64))
            }
            .frame(maxWidth: .infinity)
        }
    }
}

struct VolumeWidget: View {
    @ObservedObject var volumeProvider: VolumeProvider
    var titleAlignment: Alignment = .leading

    private var volumeIcon: String {
        if volumeProvider.isMuted || volumeProvider.volume <= 0 { return "speaker.slash.fill" }
        if volumeProvider.volume < 0.33 { return "speaker.wave.1.fill" }
        if volumeProvider.volume < 0.66 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    var body: some View {
        WidgetCard(title: "音量", titleAlignment: titleAlignment) {
            VStack(spacing: 10) {
                Button(action: { volumeProvider.toggleMute() }) {
                    Image(systemName: volumeIcon)
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(volumeProvider.isMuted ? .red.opacity(0.7) : .white.opacity(0.72))
                }
                .buttonStyle(.plain)

                Text("\(Int(volumeProvider.volume * 100))%")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)

                Slider(value: Binding(
                    get: { Double(volumeProvider.volume) },
                    set: { volumeProvider.setVolume(Float($0)) }
                ), in: 0...1)
                .tint(.white.opacity(0.56))
            }
            .frame(maxWidth: .infinity)
        }
    }
}

struct QuickLaunchWidget: View {
    var titleAlignment: Alignment = .leading

    private let apps: [(name: String, icon: String, path: String)] = [
        ("终端", "terminal.fill", "/System/Applications/Utilities/Terminal.app"),
        ("浏览器", "globe", "default-browser"),
        ("Finder", "folder.fill", "/System/Library/CoreServices/Finder.app"),
        ("监视器", "gauge.medium", "/System/Applications/Utilities/Activity Monitor.app"),
    ]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 2)

    var body: some View {
        WidgetCard(title: "快捷启动", titleAlignment: titleAlignment) {
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(apps, id: \.name) { app in
                    Button(action: {
                        if app.path == "default-browser" {
                            if let browserURL = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!) {
                                NSWorkspace.shared.openApplication(at: browserURL, configuration: .init())
                            }
                        } else {
                            NSWorkspace.shared.open(URL(fileURLWithPath: app.path))
                        }
                    }) {
                        VStack(spacing: 2) {
                            Image(systemName: app.icon)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.72))
                            Text(app.name)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.48))
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(.white.opacity(0.07))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
