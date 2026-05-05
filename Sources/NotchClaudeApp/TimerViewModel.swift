import Foundation

@MainActor
final class TimerViewModel: ObservableObject {
    @Published private(set) var elapsedSeconds = 0
    @Published private(set) var remainingSeconds = 60
    @Published private(set) var isRunning = false
    @Published var mode: TimerMode = .countUp

    private var timer: Timer?

    var formattedTime: String {
        format(mode == .countUp ? elapsedSeconds : remainingSeconds)
    }

    var minutesText: String {
        String(format: "%02d", currentSeconds / 60)
    }

    var secondsText: String {
        String(format: "%02d", currentSeconds % 60)
    }

    var collapsedStatusText: String? {
        if isRunning {
            return "\(mode.shortTitle) \(formattedTime)"
        }
        if mode == .countdown && remainingSeconds == 0 {
            return "倒计时结束"
        }
        return nil
    }

    private var currentSeconds: Int {
        mode == .countUp ? elapsedSeconds : remainingSeconds
    }

    func toggle() {
        isRunning ? pause() : start()
    }

    func reset() {
        pause()
        elapsedSeconds = 0
        remainingSeconds = 0
    }

    func setCountUp() {
        mode = .countUp
        pause()
    }

    func setCountdown(minutes: Int) {
        mode = .countdown
        remainingSeconds = max(0, minutes * 60)
        pause()
    }

    func adjustMinutes(_ delta: Int) {
        adjustCountdown(by: delta * 60)
    }

    func adjustSeconds(_ delta: Int) {
        adjustCountdown(by: delta)
    }

    private func start() {
        guard mode == .countUp || remainingSeconds > 0 else { return }
        isRunning = true
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    private func pause() {
        isRunning = false
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        switch mode {
        case .countUp:
            elapsedSeconds += 1
        case .countdown:
            remainingSeconds = max(0, remainingSeconds - 1)
            if remainingSeconds == 0 {
                pause()
            }
        }
    }

    private func adjustCountdown(by delta: Int) {
        // 切到倒计时只改变模式，不重置当前时间，快捷按钮后继续微调才符合预期。
        mode = .countdown
        remainingSeconds = max(0, min(99 * 60 + 59, remainingSeconds + delta))
        if remainingSeconds == 0 {
            pause()
        }
    }

    private func format(_ totalSeconds: Int) -> String {
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

enum TimerMode: String, CaseIterable, Identifiable {
    case countUp = "正计时"
    case countdown = "倒计时"

    var id: String { rawValue }

    var shortTitle: String {
        switch self {
        case .countUp: "正计时"
        case .countdown: "倒计时"
        }
    }
}
