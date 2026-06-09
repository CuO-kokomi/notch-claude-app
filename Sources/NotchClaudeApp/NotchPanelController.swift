import AppKit
import SwiftUI

final class NotchPanelController: NSObject {
    private let collapsedSize = NSSize(width: 260, height: 42)
    private var expandedSize: NSSize {
        NSSize(width: expandedWidth, height: 188)
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
            }
        )
        createPanel()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    func show() {
        position(size: collapsedSize)
        panel.orderFrontRegardless()
    }

    private func createPanel() {
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: collapsedSize),
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
        menu.addItem(.separator())

        let notifyItem = NSMenuItem(title: "完成通知", action: #selector(toggleNotify), keyEquivalent: "")
        notifyItem.target = self
        notifyItem.state = UserDefaults.standard.bool(forKey: NotificationManager.notifyKey) ? .on : .off
        menu.addItem(notifyItem)
        let soundItem = NSMenuItem(title: "提示声音", action: #selector(toggleSound), keyEquivalent: "")
        soundItem.target = self
        soundItem.state = UserDefaults.standard.bool(forKey: NotificationManager.soundKey) ? .on : .off
        menu.addItem(soundItem)
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
        let statusURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude-code-notch/status.json")
        try? FileManager.default.removeItem(at: statusURL)
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
        position(size: isExpanded ? expandedSize : collapsedSize)
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
        // 避免 hover 导致重复 resize，引发展开/收起抖动循环。
        guard expanded != isExpanded else { return }
        isExpanded = expanded
        let targetSize = expanded ? expandedSize : collapsedSize
        let frame = frameFor(size: targetSize)
        panel.setFrame(frame, display: true, animate: true)
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
        position(size: isExpanded ? expandedSize : collapsedSize)
    }

    private func updateExpandedWidth(for count: Int) {
        guard !isInAddMode else { return }
        let newWidth = Self.calculateWidth(for: count)
        guard newWidth != expandedWidth else { return }
        expandedWidth = newWidth
        if isExpanded {
            let frame = frameFor(size: expandedSize)
            panel.setFrame(frame, display: true, animate: true)
        }
    }

    private func handleAddModeChange(_ inAddMode: Bool) {
        isInAddMode = inAddMode
        let targetWidth = inAddMode ? Self.calculateWidth(for: 3) : Self.calculateWidth(for: UserDefaults.standard.stringArray(forKey: "activeWidgetIDs")?.count ?? 4)
        guard targetWidth != expandedWidth else { return }
        expandedWidth = targetWidth
        if isExpanded {
            let frame = frameFor(size: expandedSize)
            panel.setFrame(frame, display: true, animate: true)
        }
    }

    private static func calculateWidth(for widgetCount: Int) -> CGFloat {
        let count = CGFloat(max(2, min(6, widgetCount)))
        return count * widgetUnitWidth + horizontalPadding
    }
}
