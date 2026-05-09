import SwiftUI
import Combine

@MainActor
final class WidgetEnvironment: ObservableObject {
    let claudeStatus = ClaudeStatusProvider()
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

    private var cancellables = Set<AnyCancellable>()

    init() {
        claudeStatus.objectWillChange.sink { [weak self] _ in
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
    }
}
