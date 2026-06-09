import Foundation

// 启动时确保 Claude Code hook 已安装且为当前版本：
// 缺失或版本过旧时，后台运行 app 内置的安装脚本（合并式，保留其它工具的 hook）。
enum HookInstaller {
    // 必须与 install-claude-hooks.sh 的 HOOK_VERSION 及 hook 内标记保持一致。
    static let currentVersion = 4

    private static var hookURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/hooks/notch-status.sh")
    }

    static func ensureInstalled() {
        // 已是当前版本则跳过，避免每次启动重写全局 settings。
        if installedVersion() == currentVersion { return }
        runInstaller()
    }

    private static func installedVersion() -> Int? {
        guard let text = try? String(contentsOf: hookURL, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n").prefix(5) {
            guard let range = line.range(of: "notch-hook-version:") else { continue }
            let digits = line[range.upperBound...]
                .drop { !$0.isNumber }
                .prefix { $0.isNumber }
            return Int(digits)
        }
        return nil
    }

    private static func runInstaller() {
        // 仅在打包为 .app 且能定位到内置脚本时执行；裸二进制(dev)运行时静默跳过。
        guard let script = Bundle.main.url(forResource: "install-claude-hooks", withExtension: "sh") else { return }
        DispatchQueue.global(qos: .utility).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = [script.path]
            process.standardOutput = nil
            process.standardError = nil
            try? process.run()
        }
    }
}
