import SwiftUI

struct NotchPanelView: View {
    @State private var isExpanded = false
    @State private var isAddMode = false
    @State private var isLocked = false
    @State private var isDraggingWidget = false
    @State private var collapseTask: DispatchWorkItem?
    @StateObject private var widgetEnv = WidgetEnvironment()
    @StateObject private var widgetConfig = WidgetConfigurationManager()
    @AppStorage("flushToTop") private var flushToTop = false

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
        // 裁剪外层圆角，避免展开内容轻微溢出破坏灵动岛轮廓。
        .padding(1)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                ClaudeStatusIcon(status: widgetEnv.claudeStatus.status, compact: true)
                    .frame(width: 26, height: 26)
                    .padding(.leading, 13)
                Spacer()
                Image(systemName: widgetEnv.claudeStatus.status.symbolName)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(widgetEnv.claudeStatus.status.color)
                    .padding(.trailing, 13)
            }

            VStack(spacing: 1) {
                Text("Claude Code")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                Text(collapsedDetailText)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(widgetEnv.claudeStatus.status.color)
            }
            .frame(maxWidth: .infinity)
            .offset(y: 2)
        }
    }

    private var collapsedDetailText: String {
        if let timerText = widgetEnv.timerModel.collapsedStatusText {
            return "\(widgetEnv.claudeStatus.status.displayText)  \(timerText)"
        }
        return widgetEnv.claudeStatus.status.displayText
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
