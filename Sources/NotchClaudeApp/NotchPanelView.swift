import SwiftUI
import Combine

struct NotchPanelView: View {
    @State private var isExpanded = false
    @State private var isAddMode = false
    @State private var isSessionMode = false
    @State private var isLocked = false
    @State private var isDraggingWidget = false
    @State private var collapseTask: DispatchWorkItem?
    @State private var completionGlowLevel: Double = 0
    @State private var showCompletionCheck = false
    @State private var completionRevertTask: DispatchWorkItem?
    // 贴顶模式探出态：文字变化时向下伸出一行提醒，几秒后收回；待审批时持续伸出。
    @State private var isPeeking = false
    @State private var peekRetractTask: DispatchWorkItem?
    @StateObject private var widgetEnv = WidgetEnvironment()
    @StateObject private var widgetConfig = WidgetConfigurationManager()
    @AppStorage("flushToTop") private var flushToTop = false
    // 反向键：默认 false = 探出提醒开启，右键菜单可关。
    @AppStorage("peekDisabled") private var peekDisabled = false
    @AppStorage(GlassStyle.key) private var glassStyleRaw = GlassStyle.deep.rawValue
    private var glassStyle: GlassStyle { GlassStyle(rawValue: glassStyleRaw) ?? .deep }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let onExpandedChanged: (Bool) -> Void
    let onWidgetCountChanged: (Int) -> Void
    let onAddModeChanged: (Bool) -> Void
    let onSessionModeChanged: (Bool) -> Void
    // 控制器用精确岛体矩形判定的悬停（替代 SwiftUI onHover，死区不误展开）。
    let hoverInside: AnyPublisher<Bool, Never>
    // 回传探出行数给控制器算交互区域（纯数据，控制器不得借此 setFrame）。
    let onPeekChanged: (Int) -> Void

    private var usesSquareTopCorners: Bool {
        flushToTop && !isExpanded
    }

    private var panelShape: PanelShape {
        PanelShape(squareTopCorners: usesSquareTopCorners, cornerRadius: isExpanded ? 34 : 21)
    }

    var body: some View {
        // 窗口常驻最大尺寸，岛体是其中一块顶部居中的形变容器：
        // 收起 260×(42+探出)、展开充满窗口，同一个视图身份 + 同一条弹簧驱动整个 morph，
        // 才能做出原生灵动岛那种连续橡皮感（窗口在交互期间绝不 setFrame）。
        GeometryReader { geo in
            // 展开目标 = 窗口减去回弹余量（与 NotchPanelController.overshootMargin* 一致），
            // 弹簧过冲时岛体仍在窗口内，不会被边界切平。
            island
                .frame(
                    width: isExpanded ? geo.size.width - NotchPanelController.overshootMarginH * 2 : 260,
                    height: isExpanded ? geo.size.height - NotchPanelController.overshootMarginB : collapsedVisibleHeight
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .onReceive(widgetEnv.claudeStatus.events) { event in
            handleClaudeEvent(event)
        }
        .onReceive(hoverInside) { inside in
            if inside {
                // 收起态显示权限审批按钮时不展开（保留收起态的 ✓/✗ 直接操作）。
                if isExpanded || widgetEnv.permissions.pending.isEmpty { expand() }
            } else {
                scheduleCollapse()
            }
        }
        .onChange(of: widgetConfig.widgetCount) { newCount in
            onWidgetCountChanged(newCount)
        }
        .onChange(of: isAddMode) { newValue in
            onAddModeChanged(newValue)
        }
        .onChange(of: isSessionMode) { newValue in
            onSessionModeChanged(newValue)
        }
        // 会话小组件的「管理全部」按钮：切到会话管理模式（与加号模式互斥）。
        .onReceive(NotificationCenter.default.publisher(for: .notchOpenSessionManager)) { _ in
            guard isExpanded else { return }
            isAddMode = false
            isSessionMode = true
        }
        // 贴顶模式：状态/工具/目标文字变化时探出一行提醒（耗时秒数跳动不触发）。
        .onChange(of: peekTriggerKey) { _ in
            triggerPeek()
        }
        // 待审批期间持续探出不收回，处理完短暂显示后收回。
        .onChange(of: widgetEnv.permissions.pending.count) { count in
            guard flushToTop, !peekDisabled else { return }
            if count > 0 {
                setPeek(true, autoRetract: false)
            } else if isPeeking {
                schedulePeekRetract(after: 1.2)
            }
        }
        .onChange(of: peekLineCount) { lines in
            onPeekChanged(lines)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                widgetEnv.warmUp()
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: peekLineCount)
        // 不对称弹簧：展开带一点回弹（原生岛的橡皮感来源），收起干脆利落。
        .animation(expandAnimation, value: isExpanded)
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: flushToTop)
    }

    private var expandAnimation: Animation {
        if reduceMotion { return .easeInOut(duration: 0.25) }
        return isExpanded
            ? .spring(response: 0.42, dampingFraction: 0.72)
            : .spring(response: 0.32, dampingFraction: 0.85)
    }

    // 与旧窗口尺寸一致：主行 42 + 探出行各 26。
    private var collapsedVisibleHeight: CGFloat {
        42 + CGFloat(peekLineCount) * 26
    }

    private var island: some View {
        ZStack {
            // 展开态用玻璃质感；收起态贴着 notch，保持纯深色以求最高对比度。
            Group {
                if isExpanded {
                    GlassPlate(shape: panelShape, style: glassStyle)
                } else {
                    panelShape
                        .fill(.black.opacity(0.86))
                        .overlay(panelShape.stroke(.white.opacity(0.10), lineWidth: 1))
                }
            }
            // 阴影跟随同一条弹簧加深，给展开一点"浮起"的纵深感。
            .shadow(color: .black.opacity(0.35), radius: isExpanded ? 30 : 16, y: isExpanded ? 12 : 8)

            // 模糊交叉淡化：旧内容快速虚化退场，新内容稍晚入场——内容切换不和形变同帧硬切。
            if isExpanded {
                expandedContent
                    .transition(.asymmetric(
                        insertion: AnyTransition.blurFade
                            .combined(with: .scale(scale: 0.88))
                            .animation(.spring(response: 0.40, dampingFraction: 0.75).delay(0.06)),
                        removal: AnyTransition.blurFade.animation(.easeOut(duration: 0.10))
                    ))
            } else {
                collapsedContent
                    .transition(.asymmetric(
                        insertion: AnyTransition.blurFade
                            .animation(.easeOut(duration: 0.16).delay(0.08)),
                        removal: AnyTransition.blurFade.animation(.easeOut(duration: 0.10))
                    ))
            }
        }
        .clipShape(panelShape)
        // 完成发光叠在裁剪之上，绿光可溢出 notch 轮廓。
        .overlay(completionGlow)
        // 裁剪外层圆角，避免展开内容轻微溢出破坏灵动岛轮廓。
        .padding(1)
        // 悬停判定改由控制器（hoverInside 发布者）用精确岛体矩形驱动，这里不再用 onHover。
    }

    private var collapsedContent: some View {
        ZStack {
            VStack(spacing: 0) {
                Group {
                    if let request = widgetEnv.permissions.pending.first {
                        collapsedPermissionText(request)
                    } else {
                        collapsedStatusText
                    }
                }
                .frame(height: 42)
                if peekLineCount >= 1 {
                    peekLine
                }
                if peekLineCount >= 2, let request = widgetEnv.permissions.pending.first {
                    peekAlwaysAllowLine(request)
                }
            }
            // 左右图标/按钮独立于行结构：仅两行探出（文字 + 始终允许）时钉在探出区域内
            // 垂直居中（底部对齐 + 区域等高），其余情况一律相对整个岛体居中。
            if widgetEnv.permissions.pending.first != nil && peekLineCount >= 2 {
                HStack {
                    collapsedLeftItem
                    Spacer()
                    collapsedRightItem
                }
                .frame(height: CGFloat(peekLineCount) * 26)
                .frame(maxHeight: .infinity, alignment: .bottom)
            } else {
                HStack {
                    collapsedLeftItem
                    Spacer()
                    collapsedRightItem
                }
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: peekLineCount)
    }

    // 探出行数：审批时 1 行文字 +（有规则建议时）1 行"始终允许"；平时文字变化探出 1 行。
    private var peekLineCount: Int {
        guard flushToTop, !peekDisabled, !isExpanded else { return 0 }
        if let request = widgetEnv.permissions.pending.first {
            return request.alwaysAllowSuggestion != nil ? 2 : 1
        }
        return isPeeking ? 1 : 0
    }

    @ViewBuilder
    private var collapsedLeftItem: some View {
        if let request = widgetEnv.permissions.pending.first {
            Button(action: { widgetEnv.permissions.respond(request.id, decision: .allow) }) {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(.black.opacity(0.85))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.green.opacity(0.92)))
            }
            .buttonStyle(.plain)
            .padding(.leading, 10)
        } else {
            ZStack {
                ClaudeStatusIcon(status: widgetEnv.claudeStatus.status, compact: true)
                    .opacity(showCompletionCheck ? 0 : 1)
                if showCompletionCheck {
                    CompletionCheckIcon()
                }
            }
            .frame(width: 26, height: 26)
            .padding(.leading, 13)
        }
    }

    @ViewBuilder
    private var collapsedRightItem: some View {
        if let request = widgetEnv.permissions.pending.first {
            Button(action: { widgetEnv.permissions.respond(request.id, decision: .deny) }) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(.black.opacity(0.85))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.red.opacity(0.88)))
            }
            .buttonStyle(.plain)
            .padding(.trailing, 10)
        } else {
            Image(systemName: showCompletionCheck ? "checkmark" : widgetEnv.claudeStatus.status.symbolName)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(showCompletionCheck ? Color.green : widgetEnv.claudeStatus.status.color)
                .padding(.trailing, 13)
        }
    }

    // MARK: - 贴顶探出行

    // 贴顶时主行文字被物理刘海挡住，探出行在刘海下方完整显示一行提醒。
    private var peekLine: some View {
        Text(peekLineText)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(peekLineColor)
            .lineLimit(1)
            .truncationMode(.tail)
            // 左右图标/按钮全高居中后会盖到探出行两端，文字必须避开。
            .padding(.horizontal, 48)
            .frame(maxWidth: .infinity)
            .frame(height: 26)
            .transition(.opacity)
    }

    private var peekLineText: String {
        if let request = widgetEnv.permissions.pending.first {
            return request.detail.map { "\(request.toolName) 请求权限 · \($0)" }
                ?? "\(request.toolName) 请求权限"
        }
        if showCompletionCheck { return "完成" }
        return collapsedSecondLine
    }

    private var peekLineColor: Color {
        if !widgetEnv.permissions.pending.isEmpty { return .orange }
        if showCompletionCheck { return .green }
        return widgetEnv.claudeStatus.status.color
    }

    // 审批时的第二行：一键"始终允许"（带 Claude Code 的规则建议时才出现）。
    private func peekAlwaysAllowLine(_ request: PermissionRequest) -> some View {
        Button(action: { widgetEnv.permissions.respond(request.id, decision: .alwaysAllow) }) {
            Text("始终允许")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.black.opacity(0.85))
                .padding(.horizontal, 16)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.orange.opacity(0.9)))
        }
        .buttonStyle(.plain)
        // 避开两侧全高居中的 ✓/✗ 按钮。
        .padding(.horizontal, 48)
        .frame(maxWidth: .infinity)
        .frame(height: 26)
        .transition(.opacity)
    }

    // 状态/工具/目标的指纹：变化才触发探出，秒数跳动不算。
    private var peekTriggerKey: String {
        let claude = widgetEnv.claudeStatus
        return "\(claude.status.rawValue)|\(claude.tool ?? "")|\(claude.detail ?? "")|\(showCompletionCheck)"
    }

    private func triggerPeek() {
        guard flushToTop, !peekDisabled, !isExpanded else { return }
        setPeek(true, autoRetract: widgetEnv.permissions.pending.isEmpty)
    }

    private func setPeek(_ on: Bool, autoRetract: Bool) {
        peekRetractTask?.cancel()
        peekRetractTask = nil
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { isPeeking = on }
        if on && autoRetract {
            schedulePeekRetract(after: 1.5)
        }
    }

    private func schedulePeekRetract(after delay: TimeInterval) {
        peekRetractTask?.cancel()
        let task = DispatchWorkItem {
            guard widgetEnv.permissions.pending.isEmpty else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { isPeeking = false }
        }
        peekRetractTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: task)
    }

    // 权限请求：中间显示工具与命令摘要（左右 ✓/✗ 按钮在 collapsedLeftItem/RightItem）。
    private func collapsedPermissionText(_ request: PermissionRequest) -> some View {
        VStack(spacing: 1) {
            Text(collapsedPermissionTitle(request))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.orange)
                .lineLimit(1)
            Text(request.detail ?? "等待批准")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.78))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: 148)
        .offset(y: 2)
    }

    private func collapsedPermissionTitle(_ request: PermissionRequest) -> String {
        let queued = widgetEnv.permissions.pending.count - 1
        return queued > 0 ? "\(request.toolName) 请求权限 +\(queued)" : "\(request.toolName) 请求权限"
    }

    private var collapsedStatusText: some View {
        VStack(spacing: 1) {
            Text("Claude Code")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
            Text(collapsedSecondLine)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(showCompletionCheck ? Color.green : widgetEnv.claudeStatus.status.color)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        // 限定中间文字宽度，给左右图标留位，避免长命令溢出面板。
        .frame(maxWidth: 156)
        .offset(y: 2)
    }

    // 第二行 = 状态/工具文字 + 多会话数量角标（×N 跟文字同行）。
    private var collapsedSecondLine: String {
        let count = widgetEnv.claudeStatus.sessions.count
        return count >= 2 ? "\(collapsedDetailText)  ×\(count)" : collapsedDetailText
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
                // 顶部对齐：可添加项多时网格会变高，居中会把表头（打勾按钮）顶出可点区域。
                WidgetAddView(config: widgetConfig, isAddMode: $isAddMode)
                    .frame(maxHeight: .infinity, alignment: .top)
            } else if isSessionMode {
                SessionManagerView(provider: widgetEnv.sessionHistory, isSessionMode: $isSessionMode)
                    .frame(maxHeight: .infinity, alignment: .top)
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

            if !isAddMode && !isSessionMode {
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
        // 会话模式下面板常驻（搜索打字期间鼠标移出也不能塌缩）。
        guard !isAddMode && !isSessionMode && !isDraggingWidget && !isLocked else { return }
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

// 旧内容虚化退场 / 新内容清晰入场的交叉淡化（模仿原生灵动岛的内容切换）。
private struct BlurFadeModifier: ViewModifier {
    let radius: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content.blur(radius: radius).opacity(opacity)
    }
}

extension AnyTransition {
    static var blurFade: AnyTransition {
        .modifier(
            active: BlurFadeModifier(radius: 8, opacity: 0),
            identity: BlurFadeModifier(radius: 0, opacity: 1)
        )
    }
}

private struct PanelShape: Shape {
    let squareTopCorners: Bool
    var cornerRadius: CGFloat

    // 圆角参与形变动画（21 ↔ 34 连续过渡），否则轮廓在 morph 中途跳变。
    var animatableData: CGFloat {
        get { cornerRadius }
        set { cornerRadius = newValue }
    }

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
    @ObservedObject var claude: ClaudeStatusProvider
    @ObservedObject var permissions: PermissionServer
    var titleAlignment: Alignment = .leading

    var body: some View {
        WidgetCard(title: cardTitle, titleAlignment: titleAlignment) {
            if let request = permissions.pending.first {
                permissionContent(request)
            } else if claude.sessions.count >= 2 {
                sessionListContent
            } else {
                singleSessionContent
            }
        }
    }

    // 上下文用量直接挂在标题上：Claude · 上下文 23%。
    private var cardTitle: String {
        guard let percent = claude.sessions.first?.contextPercent else { return "Claude" }
        return "Claude · 上下文 \(percent)%"
    }

    // MARK: - 权限审批

    private func permissionContent(_ request: PermissionRequest) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ClaudeStatusIcon(status: .allow, compact: false)
                    .frame(width: 42, height: 42)
                VStack(alignment: .leading, spacing: 3) {
                    Text("需要授权")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                    Text(permissionSubtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }
            }
            if let detail = request.detail {
                Text(detail)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.74))
                    .lineLimit(request.alwaysAllowSuggestion != nil ? 1 : 2)
                    .truncationMode(.tail)
            }
            // 卡片宽度有限，三个按钮排不下：允许/拒绝一行，始终允许单独一行。
            HStack(spacing: 8) {
                permissionButton("允许", color: .green) {
                    permissions.respond(request.id, decision: .allow)
                }
                permissionButton("拒绝", color: .red) {
                    permissions.respond(request.id, decision: .deny)
                }
            }
            if request.alwaysAllowSuggestion != nil {
                permissionButton("始终允许", color: .orange) {
                    permissions.respond(request.id, decision: .alwaysAllow)
                }
            }
        }
    }

    private var permissionSubtitle: String {
        guard let request = permissions.pending.first else { return "" }
        let queued = permissions.pending.count - 1
        return queued > 0 ? "\(request.toolName) · 还有 \(queued) 个排队" : request.toolName
    }

    private func permissionButton(_ label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.black.opacity(0.85))
                .lineLimit(1)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity)
                .background(Capsule().fill(color.opacity(0.9)))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 单会话

    private var singleSessionContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ClaudeStatusIcon(status: claude.status, compact: false)
                    .frame(width: 42, height: 42)
                VStack(alignment: .leading, spacing: 3) {
                    Text(claude.status.displayText)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                    Text(secondaryText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.56))
                        .lineLimit(2)
                }
            }
            // 任务交回时展示 Claude 最后一条回复的摘要，"走开即用"看一眼结果。
            if claude.status == .waiting, let result = claude.sessions.first?.lastResult {
                Text(result)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(2)
                    .truncationMode(.tail)
            }
            Text(claude.status.actionText)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(claude.status.color)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    // 运行中显示当前工具与目标（如 Edit · App.swift · 12s），否则显示状态说明。
    private var secondaryText: String {
        guard claude.status == .running, let detail = claude.detail, !detail.isEmpty else {
            return claude.status.description
        }
        var line = detail
        if let toolName = claude.tool, !toolName.isEmpty {
            line = "\(toolName) · \(detail)"
        }
        if claude.toolElapsed > 0 {
            line += " · \(claude.toolElapsed)s"
        }
        return line
    }

    // MARK: - 多会话列表

    private var sessionListContent: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(claude.sessions.prefix(3)) { session in
                HStack(spacing: 8) {
                    Circle()
                        .fill(session.status.color)
                        .frame(width: 9, height: 9)
                    Text(session.projectName ?? String(session.id.prefix(8)))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Text(sessionRowText(session))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(session.status.color)
                        .lineLimit(1)
                }
            }
            if claude.sessions.count > 3 {
                Text("+\(claude.sessions.count - 3) 个会话")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
    }

    private func sessionRowText(_ session: ClaudeSession) -> String {
        if session.status == .running, let detail = session.detail, !detail.isEmpty {
            return detail.count > 12 ? String(detail.prefix(12)) + "…" : detail
        }
        return session.status.displayText
    }
}

