import Foundation

@MainActor
final class PomodoroProvider: ObservableObject {
    enum Phase: String {
        case idle = "就绪"
        case work = "专注中"
        case shortBreak = "短休息"
        case longBreak = "长休息"
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var remainingSeconds = 0
    @Published private(set) var completedPomodoros = 0
    @Published private(set) var isRunning = false

    private var timer: Timer?
    private let workDuration = 25 * 60
    private let shortBreakDuration = 5 * 60
    private let longBreakDuration = 15 * 60

    var formattedTime: String {
        let m = remainingSeconds / 60
        let s = remainingSeconds % 60
        return String(format: "%02d:%02d", m, s)
    }

    func start() {
        if phase == .idle {
            phase = .work
            remainingSeconds = workDuration
        }
        isRunning = true
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func pause() {
        isRunning = false
        timer?.invalidate()
        timer = nil
    }

    func reset() {
        pause()
        phase = .idle
        remainingSeconds = 0
        completedPomodoros = 0
    }

    func skip() {
        advancePhase()
    }

    private func tick() {
        guard remainingSeconds > 0 else {
            advancePhase()
            return
        }
        remainingSeconds -= 1
    }

    private func advancePhase() {
        switch phase {
        case .idle:
            break
        case .work:
            completedPomodoros += 1
            if completedPomodoros % 4 == 0 {
                phase = .longBreak
                remainingSeconds = longBreakDuration
            } else {
                phase = .shortBreak
                remainingSeconds = shortBreakDuration
            }
        case .shortBreak, .longBreak:
            phase = .work
            remainingSeconds = workDuration
        }
    }
}
