import AppKit
import SwiftUI

final class NotchPanelController: NSObject {
    private let collapsedSize = NSSize(width: 260, height: 42)
    private let expandedSize = NSSize(width: 720, height: 188)
    private var panel: NSPanel!
    private var rootView: NotchPanelView!
    private var isExpanded = false

    override init() {
        super.init()
        rootView = NotchPanelView(onExpandedChanged: { [weak self] isExpanded in
            self?.resize(expanded: isExpanded)
        })
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
        let y = frame.maxY - size.height - 9
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    private func screenForPanel() -> NSScreen {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    @objc private func screenParametersChanged() {
        position(size: isExpanded ? expandedSize : collapsedSize)
    }
}
