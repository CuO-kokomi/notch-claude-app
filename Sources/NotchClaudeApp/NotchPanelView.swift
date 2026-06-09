import SwiftUI

struct NotchPanelView: View {
    @State private var isExpanded = false
    @State private var isAddMode = false
    @State private var isLocked = false
    @State private var isDraggingWidget = false
    @State private var collapseTask: DispatchWorkItem?
    @State private var completionGlowLevel: Double = 0
    @State private var showCompletionCheck = false
    @State private var completionRevertTask: DispatchWorkItem?
    @StateObject private var widgetEnv = WidgetEnvironment()
    @StateObject private var widgetConfig = WidgetConfigurationManager()
    @AppStorage("flushToTop") private var flushToTop = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let onExpandedChanged: (Bool) -> Void
    let onWidgetCountChanged: (Int) -> Void
    let onAddModeChanged: (Bool) -> Void

    private var usesSquareTopCorners: Bool {
        flushToTop && !isExpanded
    }

    private var panelShape: PanelShape {
        PanelShape(squareTopCorners: usesSquareTopCorners, cornerRadius: isExpanded ? 34 : 21)
    }

    var body: some View {
        ZStack {
            panelShape
                .fill(.black.opacity(0.86))
                .overlay(
                    panelShape
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
        .clipShape(panelShape)
        // 完成发光叠在裁剪之上，绿光可溢出 notch 轮廓。
        .overlay(completionGlow)
        // 裁剪外层圆角，避免展开内容轻微溢出破坏灵动岛轮廓。
        .padding(1)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onReceive(widgetEnv.claudeStatus.events) { event in
            handleClaudeEvent(event)
        }
        .onHover { hovering in
            hovering ? expand() : scheduleCollapse()
        }
        .onChange(of: widgetConfig.widgetCount) { newCount in
            onWidgetCountChanged(newCount)
        }
        .onChange(of: isAddMode) { newValue in
            onAddModeChanged(newValue)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                widgetEnv.warmUp()
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: isExpanded)
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: flushToTop)
    }

    private var collapsedContent: some View {
        ZStack {
            HStack {
                ZStack {
                    ClaudeStatusIcon(status: widgetEnv.claudeStatus.status, compact: true)
                        .opacity(showCompletionCheck ? 0 : 1)
                    if showCompletionCheck {
                        CompletionCheckIcon()
                    }
                }
                .frame(width: 26, height: 26)
                .padding(.leading, 13)
                Spacer()
                Image(systemName: showCompletionCheck ? "checkmark" : widgetEnv.claudeStatus.status.symbolName)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(showCompletionCheck ? Color.green : widgetEnv.claudeStatus.status.color)
                    .padding(.trailing, 13)
            }

            VStack(spacing: 1) {
                Text("Claude Code")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                Text(collapsedDetailText)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(showCompletionCheck ? Color.green : widgetEnv.claudeStatus.status.color)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            // 限定中间文字宽度，给左右图标留位，避免长命令溢出面板。
            .frame(maxWidth: 156)
            .offset(y: 2)
        }
    }

    private var collapsedDetailText: String {
        if showCompletionCheck {
            return "完成"
        }
        let claude = widgetEnv.claudeStatus
        // 运行中优先显示当前工具目标 + 已耗时（如 App.swift  12s）。
        // 收起态很窄，先把 detail 截短，保证耗时不被挤掉。
        if claude.status == .running, let detail = claude.detail, !detail.isEmpty {
            let short = detail.count > 14 ? String(detail.prefix(14)) + "…" : detail
            return claude.toolElapsed > 0 ? "\(short)  \(claude.toolElapsed)s" : short
        }
        if let timerText = widgetEnv.timerModel.collapsedStatusText {
            return "\(claude.status.displayText)  \(timerText)"
        }
        return claude.status.displayText
    }

    private var expandedContent: some View {
        ZStack {
            if isAddMode {
                WidgetAddView(config: widgetConfig, isAddMode: $isAddMode)
            } else {
                WidgetDragContainer(
                    config: widgetConfig,
                    widgetEnv: widgetEnv,
                    isDragging: $isDraggingWidget,
                    titleAlignmentFor: titleAlignment
                )
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }

            if !isAddMode {
                VStack {
                    Spacer()
                    HStack {
                        Button(action: { isLocked.toggle() }) {
                            Image(systemName: isLocked ? "lock.fill" : "lock.open.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(isLocked ? .orange.opacity(0.82) : .white.opacity(0.38))
                                .frame(width: 24, height: 24)
                                .background(Circle().fill(.white.opacity(isLocked ? 0.10 : 0.05)))
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        if !widgetConfig.inactiveDescriptors.isEmpty {
                            Button(action: { isAddMode = true }) {
                                Image(systemName: "plus")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.48))
                                    .frame(width: 26, height: 26)
                                    .background(Circle().fill(.white.opacity(0.08)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
                }
            }
        }
    }

    private func titleAlignment(for index: Int) -> Alignment {
        let count = widgetConfig.activeDescriptors.count
        if count <= 1 { return .leading }
        let midpoint = Double(count - 1) / 2.0
        if Double(index) < midpoint { return .leading }
        if Double(index) > midpoint { return .trailing }
        return .center
    }

    private func expand() {
        collapseTask?.cancel()
        collapseTask = nil
        guard !isExpanded else { return }
        isExpanded = true
        onExpandedChanged(true)
    }

    private func scheduleCollapse() {
        guard !isAddMode && !isDraggingWidget && !isLocked else { return }
        collapseTask?.cancel()
        let task = DispatchWorkItem {
            guard isExpanded else { return }
            isExpanded = false
            onExpandedChanged(false)
        }
        collapseTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: task)
    }

    // 完成时溢出 notch 的绿光描边脉冲，由 completionGlowLevel 驱动呼吸。
    private var completionGlow: some View {
        panelShape
            .stroke(Color.green, lineWidth: 2.5)
            .shadow(color: .green.opacity(0.85), radius: 14)
            .opacity(completionGlowLevel * 0.9)
            .allowsHitTesting(false)
    }

    private func handleClaudeEvent(_ event: ClaudeEvent) {
        // 仅在收起态做完成动画；展开态用户正盯着面板，不打扰。
        guard case .completed = event, !isExpanded else { return }
        triggerCompletionFlash()
    }

    private func triggerCompletionFlash() {
        completionRevertTask?.cancel()
        completionGlowLevel = 0
        showCompletionCheck = true

        if reduceMotion {
            // 减弱动态效果：单次淡入淡出，无弹跳呼吸。
            withAnimation(.easeInOut(duration: 0.35)) { completionGlowLevel = 1 }
        } else {
            // 0→1→0 呼吸两轮（autoreverses 偶数次回到 0）。
            withAnimation(.easeInOut(duration: 0.45).repeatCount(4, autoreverses: true)) {
                completionGlowLevel = 1
            }
        }

        let revert = DispatchWorkItem {
            withAnimation(.easeOut(duration: 0.4)) {
                completionGlowLevel = 0
                showCompletionCheck = false
            }
        }
        completionRevertTask = revert
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.9, execute: revert)
    }
}

struct WidgetDragContainer: View {
    @ObservedObject var config: WidgetConfigurationManager
    @ObservedObject var widgetEnv: WidgetEnvironment
    @Binding var isDragging: Bool
    let titleAlignmentFor: (Int) -> Alignment

    @State private var draggingID: String?
    @State private var dragTranslation: CGFloat = 0
    @State private var dragVerticalOffset: CGFloat = 0
    @State private var swapAdjustment: CGFloat = 0
    @State private var widgetWidth: CGFloat = 0

    private var isRemoveReady: Bool {
        guard config.activeWidgetIDs.count > WidgetConfigurationManager.minWidgets else { return false }
        return abs(dragVerticalOffset) > 60
    }

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 12) {
                ForEach(Array(config.activeDescriptors.enumerated()), id: \.element.id) { index, desc in
                    let isDragTarget = draggingID == desc.id
                    desc.viewBuilder(widgetEnv, titleAlignmentFor(index))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .opacity(isDragTarget ? (isRemoveReady ? 0.15 : 0.4) : 1.0)
                        .scaleEffect(isDragTarget ? (isRemoveReady ? 0.85 : 0.95) : 1.0)
                        .overlay(
                            Group {
                                if isDragTarget && isRemoveReady {
                                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                                        .stroke(.red.opacity(0.6), lineWidth: 2)
                                        .overlay(
                                            Image(systemName: "trash")
                                                .font(.system(size: 18, weight: .semibold))
                                                .foregroundStyle(.red.opacity(0.7))
                                        )
                                }
                            }
                        )
                        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isRemoveReady)
                        .gesture(
                            DragGesture(coordinateSpace: .global)
                                .onChanged { value in
                                    if draggingID == nil {
                                        draggingID = desc.id
                                        isDragging = true
                                        let count = CGFloat(config.activeDescriptors.count)
                                        widgetWidth = (geo.size.width - 12 * (count - 1)) / count
                                        swapAdjustment = 0
                                    }
                                    dragTranslation = value.translation.width
                                    dragVerticalOffset = value.translation.height
                                    handleReorder()
                                }
                                .onEnded { _ in
                                    if isRemoveReady {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                            if let id = draggingID {
                                                config.remove(id)
                                            }
                                        }
                                    }
                                    draggingID = nil
                                    isDragging = false
                                    dragTranslation = 0
                                    dragVerticalOffset = 0
                                    swapAdjustment = 0
                                }
                        )
                }
            }
        }
    }

    private func handleReorder() {
        guard let id = draggingID,
              let currentIndex = config.activeWidgetIDs.firstIndex(of: id) else { return }

        let step = widgetWidth + 12
        let effectiveOffset = dragTranslation - swapAdjustment

        if effectiveOffset > step / 2, currentIndex < config.activeWidgetIDs.count - 1 {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                config.activeWidgetIDs.move(
                    fromOffsets: IndexSet(integer: currentIndex),
                    toOffset: currentIndex + 2
                )
            }
            swapAdjustment += step
        } else if effectiveOffset < -step / 2, currentIndex > 0 {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                config.activeWidgetIDs.move(
                    fromOffsets: IndexSet(integer: currentIndex),
                    toOffset: currentIndex - 1
                )
            }
            swapAdjustment -= step
        }
    }
}

private struct PanelShape: Shape {
    let squareTopCorners: Bool
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        if squareTopCorners {
            return SquareTopPanelShape(bottomRadius: cornerRadius).path(in: rect)
        }
        return RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).path(in: rect)
    }
}

private struct SquareTopPanelShape: Shape {
    let bottomRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let bottomRadius = min(bottomRadius, rect.height / 2)

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottomRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - bottomRadius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + bottomRadius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - bottomRadius),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.closeSubpath()
        return path
    }
}

// 任务完成时短暂替换状态图标的绿色对勾，带一次弹性放大。
struct CompletionCheckIcon: View {
    @State private var popped = false

    var body: some View {
        ZStack {
            Circle().fill(Color.green)
            Circle().stroke(.white.opacity(0.16), lineWidth: 1)
            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(.black.opacity(0.85))
        }
        .scaleEffect(popped ? 1.0 : 0.5)
        .onAppear {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.5)) { popped = true }
        }
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
    var toolName: String? = nil
    var detail: String? = nil
    var elapsed: Int = 0
    var titleAlignment: Alignment = .leading

    var body: some View {
        WidgetCard(title: "Claude", titleAlignment: titleAlignment) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    ClaudeStatusIcon(status: status, compact: false)
                        .frame(width: 42, height: 42)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(status.displayText)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.white)
                        Text(secondaryText)
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

    // 运行中显示当前工具与目标（如 Edit · App.swift · 12s），否则显示状态说明。
    private var secondaryText: String {
        guard status == .running, let detail, !detail.isEmpty else {
            return status.description
        }
        var line = detail
        if let toolName, !toolName.isEmpty {
            line = "\(toolName) · \(detail)"
        }
        if elapsed > 0 {
            line += " · \(elapsed)s"
        }
        return line
    }
}
