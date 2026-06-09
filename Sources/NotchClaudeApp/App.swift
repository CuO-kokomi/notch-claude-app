import AppKit
import SwiftUI

@main
struct NotchClaudeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panelController: NotchPanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // 尽早注册通知/声音开关默认值，确保右键菜单勾选与实际默认一致。
        NotificationManager.registerDefaults()
        // 启动即确保 Claude Code hook 安装/升级到当前版本（合并式，保留其它工具 hook）。
        HookInstaller.ensureInstalled()
        panelController = NotchPanelController()
        panelController?.show()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
