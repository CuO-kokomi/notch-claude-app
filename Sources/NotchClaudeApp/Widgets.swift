import SwiftUI

struct CalendarWidget: View {
    private let calendar = Calendar.current
    private let weekdays = ["日", "一", "二", "三", "四", "五", "六"]

    private var monthTitle: String {
        Date().formatted(.dateTime.year().month(.wide).locale(Locale(identifier: "zh_CN")))
    }

    private var days: [CalendarDay] {
        let today = Date()
        guard let monthInterval = calendar.dateInterval(of: .month, for: today),
              let firstWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start),
              let lastWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.end.addingTimeInterval(-1)) else {
            return []
        }

        var result: [CalendarDay] = []
        var date = firstWeek.start
        while date < lastWeek.end {
            result.append(CalendarDay(
                id: date,
                day: calendar.component(.day, from: date),
                isCurrentMonth: calendar.isDate(date, equalTo: today, toGranularity: .month),
                isToday: calendar.isDateInToday(date)
            ))
            date = calendar.date(byAdding: .day, value: 1, to: date) ?? lastWeek.end
        }
        return result
    }

    var body: some View {
        WidgetCard(title: monthTitle) {
            VStack(spacing: 5) {
                HStack(spacing: 0) {
                    ForEach(weekdays, id: \.self) { weekday in
                        Text(weekday)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.46))
                            .frame(maxWidth: .infinity)
                    }
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 7), spacing: 1) {
                    ForEach(days) { day in
                        Text("\(day.day)")
                            .font(.system(size: 9, weight: day.isToday ? .bold : .medium, design: .rounded))
                            .foregroundStyle(day.isCurrentMonth ? .white.opacity(day.isToday ? 1 : 0.76) : .white.opacity(0.22))
                            .frame(height: 13)
                            .frame(maxWidth: .infinity)
                            .background(
                                Circle()
                                    .fill(day.isToday ? Color.orange.opacity(0.95) : .clear)
                            )
                    }
                }
            }
        }
    }
}

private struct CalendarDay: Identifiable {
    let id: Date
    let day: Int
    let isCurrentMonth: Bool
    let isToday: Bool
}

struct TimerWidget: View {
    @ObservedObject var timerModel: TimerViewModel

    var body: some View {
        WidgetCard(title: "计时器", titleAlignment: .trailing) {
            VStack(spacing: 6) {
                HStack(spacing: 4) {
                    QuickTimerButton(title: "正计") { timerModel.setCountUp() }
                    QuickTimerButton(title: "1分") { timerModel.setCountdown(minutes: 1) }
                    QuickTimerButton(title: "5分") { timerModel.setCountdown(minutes: 5) }
                    QuickTimerButton(title: "15分") { timerModel.setCountdown(minutes: 15) }
                }
                .frame(maxWidth: .infinity)

                HStack(alignment: .center, spacing: 2) {
                    TimeUnitControl(value: timerModel.minutesText, label: "分") {
                        timerModel.adjustMinutes(1)
                    } decrement: {
                        timerModel.adjustMinutes(-1)
                    }

                    Text(":")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.72))
                        .frame(width: 10)
                        .offset(y: -1)

                    TimeUnitControl(value: timerModel.secondsText, label: "秒") {
                        timerModel.adjustSeconds(1)
                    } decrement: {
                        timerModel.adjustSeconds(-1)
                    }
                }
                .frame(maxWidth: .infinity)

                HStack(spacing: 10) {
                    TimerActionButton(title: timerModel.isRunning ? "暂停" : "开始") {
                        timerModel.toggle()
                    }
                    TimerActionButton(title: "重置") {
                        timerModel.reset()
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }
}

private struct TimerActionButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.82))
                .frame(width: 44, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.white.opacity(0.07))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(.white.opacity(0.18), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct QuickTimerButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 8, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .foregroundStyle(.white.opacity(0.82))
                .frame(minWidth: 27, minHeight: 20)
                .padding(.horizontal, 2)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(.white.opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(.white.opacity(0.10), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct TimeUnitControl: View {
    let value: String
    let label: String
    let increment: () -> Void
    let decrement: () -> Void

    var body: some View {
        VStack(spacing: 1) {
            StepButton(systemName: "chevron.up", action: increment)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .frame(width: 34)
                Text(label)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.42))
            }
            StepButton(systemName: "chevron.down", action: decrement)
        }
        .frame(width: 48)
    }
}

private struct StepButton: View {
    let systemName: String
    let action: () -> Void
    @State private var isPressing = false
    @State private var repeatTask: DispatchWorkItem?

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 7, weight: .bold))
            .frame(width: 26, height: 11)
            .background(Capsule().fill(.white.opacity(isPressing ? 0.18 : 0.11)))
            .foregroundStyle(.white.opacity(0.72))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !isPressing else { return }
                        isPressing = true
                        action()
                        scheduleRepeat(after: 0.35)
                    }
                    .onEnded { _ in
                        stopRepeating()
                    }
            )
    }

    private func scheduleRepeat(after delay: TimeInterval) {
        repeatTask?.cancel()
        let task = DispatchWorkItem {
            guard isPressing else { return }
            action()
            scheduleRepeat(after: 0.12)
        }
        repeatTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: task)
    }

    private func stopRepeating() {
        isPressing = false
        repeatTask?.cancel()
        repeatTask = nil
    }
}

struct SystemStatsWidget: View {
    @ObservedObject var systemStats: SystemStatsProvider

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 2)

    var body: some View {
        WidgetCard(title: "系统", titleAlignment: .trailing) {
            LazyVGrid(columns: columns, spacing: 6) {
                SystemMetricTile(systemName: "cpu", title: "CPU", value: systemStats.cpuText)
                SystemMetricTile(systemName: "memorychip", title: "内存", value: systemStats.memoryText)
                SystemMetricTile(systemName: "arrow.up", title: "上传", value: systemStats.uploadText)
                SystemMetricTile(systemName: "arrow.down", title: "下载", value: systemStats.downloadText)
            }
        }
    }
}

private struct SystemMetricTile: View {
    let systemName: String
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.72))
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.48))
            Text(value)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.58)
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(0.07))
        )
    }
}

struct WidgetCard<Content: View>: View {
    let title: String
    var titleAlignment: Alignment = .leading
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.56))
                .frame(maxWidth: .infinity, alignment: titleAlignment)
            content
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.white.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct StatPill: View {
    let text: String
    let fontSize: CGFloat

    var body: some View {
        Text(text)
            .font(.system(size: fontSize, weight: .bold, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Capsule()
                    .fill(.white.opacity(0.08))
            )
    }
}
