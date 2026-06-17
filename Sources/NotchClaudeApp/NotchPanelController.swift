import AppKit
import SwiftUI
import Combine

final class NotchPanelController: NSObject {
    // 窗口常驻最大展开尺寸，多余部分透明（鼠标监视器负责点击穿透）；
    // 收起/展开/探出全部是岛体的纯 SwiftUI 形变动画，交互期间绝不 setFrame——
    // 窗口动画会和 NSHostingView 的约束更新互相重入直接崩溃，也无法与内容弹簧同步。
    private let collapsedIslandWidth: CGFloat = 260
    // 回弹余量：展开弹簧有 ~4% 过冲，窗口比岛体目标大一圈，避免过冲瞬间被窗口边界切平。
    // 必须与 NotchPanelView 的 overshootMarginH/B 保持一致。
    static let overshootMarginH: CGFloat = 24
    static let overshootMarginB: CGFloat = 16
    private var expandedSize: NSSize {
        NSSize(width: expandedWidth + Self.overshootMarginH * 2, height: 188 + Self.overshootMarginB)
    }
    private var expandedWidth: CGFloat = 720
    private var isInAddMode = false
    private var panel: NSPanel!
    private var rootView: NotchPanelView!
    private var isExpanded = false
    private var flushToTop: Bool {
        UserDefaults.standard.bool(forKey: "flushToTop")
    }

    private static let widgetUnitWidth: CGFloat = 170
    private static let horizontalPadding: CGFloat = 40

    // 收起态可见岛体高度（42 + 探出行×26），由视图回传；窗口其余部分是透明死区。
    private var visibleCollapsedHeight: CGFloat = 42
    private var mouseMonitors: [Any] = []
    // 鼠标是否落在当前可见岛体矩形内——驱动展开/收起。比 SwiftUI onHover 精确，
    // 死区（透明窗口的展开区范围）永远判 false，不会误展开。
    private let hoverInside = CurrentValueSubject<Bool, Never>(false)

    override init() {
        super.init()
        let widgetCount = UserDefaults.standard.stringArray(forKey: "activeWidgetIDs")?.count ?? 4
        expandedWidth = Self.calculateWidth(for: widgetCount)
        rootView = NotchPanelView(
            onExpandedChanged: { [weak self] isExpanded in
                self?.resize(expanded: isExpanded)
            },
            onWidgetCountChanged: { [weak self] count in
                self?.updateExpandedWidth(for: count)
            },
            onAddModeChanged: { [weak self] inAddMode in
                self?.handleAddModeChange(inAddMode)
            },
            hoverInside: hoverInside.eraseToAnyPublisher(),
            onPeekChanged: { [weak self] lines in
                // 仅更新交互区域高度，绝不在这里 setFrame。
                self?.visibleCollapsedHeight = 42 + CGFloat(lines) * 26
                self?.updateMouseIgnoring()
            }
        )
        createPanel()
        installMouseMonitors()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    func show() {
        position(size: expandedSize)
        panel.orderFrontRegardless()
    }

    private func createPanel() {
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: expandedSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .statusBar
        // 允许面板跨桌面和全屏应用停留在顶部。
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false
        let hostingView = NotchHostingView(rootView: rootView)
        // 窗口尺寸全程由 setFrame 手动控制；禁用 NSHostingView 的内容尺寸约束，
        // 否则探出伸缩时它在 updateConstraints 里重算 minSize 会触发约束重入崩溃。
        hostingView.sizingOptions = []
        hostingView.menu = contextMenu()
        panel.contentView = hostingView
    }

    private final class NotchHostingView: NSHostingView<NotchPanelView> {
        // SwiftUI 承载视图默认右键菜单不稳定，这里直接拦截右键事件。
        override func rightMouseDown(with event: NSEvent) {
            guard let menu else { return }
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        }
    }

    private func contextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "重置 Claude 状态", action: #selector(resetClaudeStatus), keyEquivalent: ""))
        menu.items.last?.target = self
        menu.addItem(NSMenuItem(title: "安装 / 升级 hook", action: #selector(installHook), keyEquivalent: ""))
        menu.items.last?.target = self
        let flushItem = NSMenuItem(title: "贴顶显示", action: #selector(toggleFlushToTop), keyEquivalent: "")
        flushItem.target = self
        flushItem.state = flushToTop ? .on : .off
        menu.addItem(flushItem)
        // 贴顶时文字变化向下探出一行提醒；不喜欢可以关掉。
        let peekItem = NSMenuItem(title: "探出提醒", action: #selector(togglePeek), keyEquivalent: "")
        peekItem.target = self
        peekItem.state = UserDefaults.standard.bool(forKey: "peekDisabled") ? .off : .on
        menu.addItem(peekItem)
        menu.addItem(.separator())

        let notifyItem = NSMenuItem(title: "完成通知", action: #selector(toggleNotify), keyEquivalent: "")
        notifyItem.target = self
        notifyItem.state = UserDefaults.standard.bool(forKey: NotificationManager.notifyKey) ? .on : .off
        menu.addItem(notifyItem)
        let soundItem = NSMenuItem(title: "提示声音", action: #selector(toggleSound), keyEquivalent: "")
        soundItem.target = self
        soundItem.state = UserDefaults.standard.bool(forKey: NotificationManager.soundKey) ? .on : .off
        menu.addItem(soundItem)
        // 上下文窗口大小 hook 无法可靠探测；1M 订阅用户勾上后百分比按 1M 计算。
        let context1MItem = NSMenuItem(title: "上下文按 1M 窗口计算", action: #selector(toggleContext1M), keyEquivalent: "")
        context1MItem.target = self
        context1MItem.state = UserDefaults.standard.bool(forKey: ClaudeStatusProvider.context1MKey) ? .on : .off
        menu.addItem(context1MItem)
        menu.addItem(.separator())

        // 展开态玻璃质感：暗色玻璃 / 明亮 Liquid Glass 切换。
        let glassParent = NSMenuItem(title: "展开玻璃质感", action: nil, keyEquivalent: "")
        let glassSub = NSMenu()
        let current = GlassStyle.current
        for (style, title) in [(GlassStyle.deep, "厚玻璃"), (GlassStyle.sheer, "薄玻璃")] {
            let item = NSMenuItem(title: title, action: #selector(selectGlassStyle(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = style.rawValue
            item.state = current == style ? .on : .off
            glassSub.addItem(item)
        }
        glassParent.submenu = glassSub
        menu.addItem(glassParent)
        menu.addItem(.separator())
        let aboutItem = NSMenuItem(title: "关于灵动岛", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出灵动岛", action: #selector(quitApp), keyEquivalent: "q"))
        menu.items.last?.target = self
        return menu
    }

    @objc private func resetClaudeStatus() {
        // v5 起状态按会话存放在 sessions/ 目录，连同 v4 的旧单文件一并清掉。
        let fm = FileManager.default
        try? fm.removeItem(at: ClaudeStatusProvider.sessionsDir)
        let legacyURL = fm.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude-code-notch/status.json")
        try? fm.removeItem(at: legacyURL)
    }

    @objc private func installHook() {
        HookInstaller.install { [weak self] ok, message in
            self?.presentHookResult(ok: ok, message: message)
        }
    }

    private func presentHookResult(ok: Bool, message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = ok ? .informational : .warning
        alert.messageText = ok ? "Claude Code hook 已安装 / 升级" : "安装失败"
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    @objc private func toggleFlushToTop() {
        UserDefaults.standard.set(!flushToTop, forKey: "flushToTop")
        position(size: expandedSize)
        (panel.contentView as? NotchHostingView)?.menu = contextMenu()
    }

    @objc private func toggleNotify() {
        let key = NotificationManager.notifyKey
        UserDefaults.standard.set(!UserDefaults.standard.bool(forKey: key), forKey: key)
        (panel.contentView as? NotchHostingView)?.menu = contextMenu()
    }

    @objc private func toggleSound() {
        let key = NotificationManager.soundKey
        UserDefaults.standard.set(!UserDefaults.standard.bool(forKey: key), forKey: key)
        (panel.contentView as? NotchHostingView)?.menu = contextMenu()
    }

    @objc private func togglePeek() {
        let key = "peekDisabled"
        UserDefaults.standard.set(!UserDefaults.standard.bool(forKey: key), forKey: key)
        (panel.contentView as? NotchHostingView)?.menu = contextMenu()
    }

    @objc private func toggleContext1M() {
        let key = ClaudeStatusProvider.context1MKey
        UserDefaults.standard.set(!UserDefaults.standard.bool(forKey: key), forKey: key)
        (panel.contentView as? NotchHostingView)?.menu = contextMenu()
    }

    @objc private func selectGlassStyle(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String else { return }
        UserDefaults.standard.set(raw, forKey: GlassStyle.key)
        (panel.contentView as? NotchHostingView)?.menu = contextMenu()
    }

    private static let repoURL = "https://github.com/CuO-kokomi/notch-claude-app"
    private static let latestReleaseAPI = "https://api.github.com/repos/CuO-kokomi/notch-claude-app/releases/latest"

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "灵动岛 Claude  v\(appVersion)"
        alert.informativeText = """
        为 MacBook notch 设计的 Claude Code 状态悬浮面板。
        收起贴合 notch 显示实时状态，悬停展开为可自由组合的信息面板。

        任务完成 / 需要授权 / 出错时，系统通知 + 提示声音 + notch 完成动画。
        """
        if let icon = NSApp.applicationIconImage { alert.icon = icon }
        alert.addButton(withTitle: "检查更新")
        alert.addButton(withTitle: "项目主页")
        alert.addButton(withTitle: "完成")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            checkForUpdate()
        case .alertSecondButtonReturn:
            openURL(Self.repoURL)
        default:
            break
        }
    }

    private func checkForUpdate() {
        guard let url = URL(string: Self.latestReleaseAPI) else { return }
        var request = URLRequest(url: url, timeoutInterval: 12)
        // GitHub API 需要 User-Agent，否则可能 403。
        request.setValue("notch-claude-app", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.presentUpdateResult(data: data, response: response, error: error)
            }
        }.resume()
    }

    private func presentUpdateResult(data: Data?, response: URLResponse?, error: Error?) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0

        guard error == nil, statusCode == 200, let data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String else {
            alert.messageText = "暂时无法检查更新"
            alert.informativeText = statusCode == 404 ? "项目尚未发布 Release。" : "请检查网络后重试。"
            alert.addButton(withTitle: "好")
            alert.runModal()
            return
        }

        if Self.isNewer(tag, than: appVersion) {
            alert.messageText = "发现新版本 \(tag)"
            alert.informativeText = "当前 v\(appVersion)，可前往 GitHub 下载最新版本。"
            alert.addButton(withTitle: "前往下载")
            alert.addButton(withTitle: "稍后")
            if alert.runModal() == .alertFirstButtonReturn {
                openURL((json["html_url"] as? String) ?? "\(Self.repoURL)/releases/latest")
            }
        } else {
            alert.messageText = "已是最新版本"
            alert.informativeText = "当前 v\(appVersion) 已是最新。"
            alert.addButton(withTitle: "好")
            alert.runModal()
        }
    }

    // 比较 GitHub tag（如 v4.1）与当前版本（如 4.0），按数字分段比较。
    private static func isNewer(_ tag: String, than current: String) -> Bool {
        func parts(_ s: String) -> [Int] {
            s.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
                .split(separator: ".")
                .map { Int($0.prefix { $0.isNumber }) ?? 0 }
        }
        let latest = parts(tag), cur = parts(current)
        for i in 0..<max(latest.count, cur.count) {
            let l = i < latest.count ? latest[i] : 0
            let c = i < cur.count ? cur[i] : 0
            if l != c { return l > c }
        }
        return false
    }

    private func openURL(_ string: String) {
        if let url = URL(string: string) { NSWorkspace.shared.open(url) }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func resize(expanded: Bool) {
        // 窗口不动，只记录状态供鼠标交互区域计算；形变动画全在 SwiftUI 内部。
        guard expanded != isExpanded else { return }
        isExpanded = expanded
        updateMouseIgnoring()
    }

    // MARK: - 透明死区点击穿透

    // 窗口常驻最大尺寸，岛体以外的透明区会吞掉点击（macOS 不会自动按像素透明度穿透）。
    // 全局+本地鼠标监视：鼠标不在可见岛体上时让整个窗口忽略鼠标事件。
    private func installMouseMonitors() {
        let global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved], handler: { [weak self] _ in
            self?.updateMouseIgnoring()
        })
        let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved], handler: { [weak self] event in
            self?.updateMouseIgnoring()
            return event
        })
        mouseMonitors = [global, local].compactMap { $0 }
    }

    private func updateMouseIgnoring() {
        let frame = panel.frame
        // 展开态岛体 = 窗口减去回弹余量；收起态是顶部居中的 260 宽条（高度含探出行）。
        let interactive: NSRect
        if isExpanded {
            interactive = NSRect(
                x: frame.minX + Self.overshootMarginH,
                y: frame.minY + Self.overshootMarginB,
                width: frame.width - Self.overshootMarginH * 2,
                height: frame.height - Self.overshootMarginB
            )
        } else {
            interactive = NSRect(
                x: frame.midX - collapsedIslandWidth / 2,
                y: frame.maxY - visibleCollapsedHeight,
                width: collapsedIslandWidth,
                height: visibleCollapsedHeight
            )
        }
        let inside = interactive.contains(NSEvent.mouseLocation)
        if panel.ignoresMouseEvents == inside {
            panel.ignoresMouseEvents = !inside
        }
        // 同一份精确判定驱动展开/收起（替代 SwiftUI onHover，杜绝死区误展开）。
        if hoverInside.value != inside {
            hoverInside.send(inside)
        }
    }

    private func position(size: NSSize) {
        panel.setFrame(frameFor(size: size), display: true)
    }

    private func frameFor(size: NSSize) -> NSRect {
        let screen = screenForPanel()
        let frame = screen.frame
        let x = frame.midX - size.width / 2
        let y = frame.maxY - size.height - (flushToTop ? -7 : 9)
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    private func screenForPanel() -> NSScreen {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    @objc private func screenParametersChanged() {
        position(size: expandedSize)
    }

    private func updateExpandedWidth(for count: Int) {
        guard !isInAddMode else { return }
        let newWidth = Self.calculateWidth(for: count)
        guard newWidth != expandedWidth else { return }
        expandedWidth = newWidth
        applyExpandedWidth()
    }

    private func handleAddModeChange(_ inAddMode: Bool) {
        isInAddMode = inAddMode
        let targetWidth = inAddMode ? Self.calculateWidth(for: 3) : Self.calculateWidth(for: UserDefaults.standard.stringArray(forKey: "activeWidgetIDs")?.count ?? 4)
        guard targetWidth != expandedWidth else { return }
        expandedWidth = targetWidth
        applyExpandedWidth()
    }

    // 窗口宽度跟随最大展开宽度；收起态（不可见）瞬切，展开态保留动画。
    private func applyExpandedWidth() {
        let frame = frameFor(size: expandedSize)
        panel.setFrame(frame, display: true, animate: isExpanded)
    }

    private static func calculateWidth(for widgetCount: Int) -> CGFloat {
        let count = CGFloat(max(2, min(6, widgetCount)))
        return count * widgetUnitWidth + horizontalPadding
    }
}
