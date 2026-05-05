import SwiftUI

struct NotchPanelView: View {
    @State private var isExpanded = false
    @State private var collapseTask: DispatchWorkItem?
    @StateObject private var claudeStatus = ClaudeStatusProvider()
    @StateObject private var timerModel = TimerViewModel()
    @StateObject private var systemStats = SystemStatsProvider()

    let onExpandedChanged: (Bool) -> Void

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: isExpanded ? 34 : 21, style: .continuous)
                .fill(.black.opacity(0.86))
                .overlay(
                    RoundedRectangle(cornerRadius: isExpanded ? 34 : 21, style: .continuous)
                        .stroke(.white.opacity(0.10), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.35), radius: 22, y: 10)

            if isExpanded {
                expandedContent
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else {
                collapsedContent
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: isExpanded ? 34 : 21, style: .continuous))
        // 裁剪外层圆角，避免展开内容轻微溢出破坏灵动岛轮廓。
        .padding(1)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onHover { hovering in
            hovering ? expand() : scheduleCollapse()
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: isExpanded)
    }

    private var collapsedContent: some View {
        ZStack {
            HStack {
                ClaudeStatusIcon(status: claudeStatus.status, compact: true)
                    .frame(width: 26, height: 26)
                    .padding(.leading, 13)
                Spacer()
                Image(systemName: claudeStatus.status.symbolName)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(claudeStatus.status.color)
                    .padding(.trailing, 13)
            }

            VStack(spacing: 1) {
                Text("Claude Code")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                Text(collapsedDetailText)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(claudeStatus.status.color)
            }
            .frame(maxWidth: .infinity)
            .offset(y: 2)
        }
    }

    private var collapsedDetailText: String {
        if let timerText = timerModel.collapsedStatusText {
            return "\(claudeStatus.status.displayText)  \(timerText)"
        }
        return claudeStatus.status.displayText
    }

    private var expandedContent: some View {
        HStack(spacing: 12) {
            ClaudeStatusWidget(status: claudeStatus.status)
            CalendarWidget()
            TimerWidget(timerModel: timerModel)
            SystemStatsWidget(systemStats: systemStats)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func expand() {
        collapseTask?.cancel()
        collapseTask = nil
        guard !isExpanded else { return }
        isExpanded = true
        onExpandedChanged(true)
    }

    private func scheduleCollapse() {
        // 留极短缓冲，避免鼠标擦过边缘时闪烁。
        collapseTask?.cancel()
        let task = DispatchWorkItem {
            guard isExpanded else { return }
            isExpanded = false
            onExpandedChanged(false)
        }
        collapseTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: task)
    }
}

struct ClaudeStatusIcon: View {
    let status: ClaudeStatus
    let compact: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(status.color.opacity(status == .idle ? 0.30 : 0.95))
            Circle()
                .stroke(.white.opacity(0.16), lineWidth: 1)
            Image(systemName: status.symbolName)
                .font(.system(size: compact ? 13 : 22, weight: .bold))
                .foregroundStyle(status == .idle ? .white.opacity(0.82) : .black.opacity(0.82))
        }
    }
}

struct ClaudeStatusWidget: View {
    let status: ClaudeStatus

    var body: some View {
        WidgetCard(title: "Claude") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    ClaudeStatusIcon(status: status, compact: false)
                        .frame(width: 42, height: 42)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(status.displayText)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.white)
                        Text(status.description)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.56))
                            .lineLimit(2)
                    }
                }
                Text(status.actionText)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(status.color)
            }
        }
    }
}
