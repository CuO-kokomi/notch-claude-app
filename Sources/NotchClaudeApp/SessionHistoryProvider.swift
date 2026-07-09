import AppKit
import Foundation
import SwiftUI

// 一条历史 Claude Code 会话的轻量元数据，从 ~/.claude/projects/*/*.jsonl 提取。
struct SessionSummary: Identifiable, Codable, Equatable {
    let id: String        // sessionId（文件名去 .jsonl）
    let path: String      // jsonl 绝对路径（缓存键）
    let title: String
    let firstMessage: String
    let cwd: String       // 真实 cwd 存在消息里；目录名编码有损，仅兜底
    let branch: String
    let messageCount: Int
    let mtime: Date
}

// 按项目（cwd）分组的会话列表，最近活动的组在前。
struct SessionGroup: Identifiable {
    var id: String { cwd }
    let cwd: String
    let name: String
    var sessions: [SessionSummary]
    var latest: Date
}

// 历史会话扫描 / 搜索 / resume（ccsm.py 的 Swift 移植）。
@MainActor
final class SessionHistoryProvider: ObservableObject {
    @Published private(set) var groups: [SessionGroup] = []
    @Published private(set) var recentSessions: [SessionSummary] = []
    @Published private(set) var isScanning = false
    @Published private(set) var totalCount = 0

    nonisolated static let skipPermissionsKey = "sessionSkipPermissions"
    nonisolated static let terminalAppKey = "resumeTerminalApp"

    // Resume 可用的终端：只列已安装的，菜单里不出现装都没装的选项。
    nonisolated static func availableTerminals() -> [ResumeTerminal] {
        ResumeTerminal.allCases.filter(\.isInstalled)
    }

    nonisolated static var preferredTerminal: ResumeTerminal {
        let saved = UserDefaults.standard.string(forKey: terminalAppKey)
            .flatMap(ResumeTerminal.init(rawValue:)) ?? .terminal
        // 选过的 app 被卸载后回退 Terminal。
        return saved.isInstalled ? saved : .terminal
    }

    nonisolated static let projectsDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/projects")
    // 与 ccsm 的 .ccsm_cache.json schema 不同，各用各的，互不污染。
    nonisolated private static let cacheURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/NotchClaude/session-cache.json")

    private var cache: [String: SessionSummary] = [:]
    private var lastScanAt: Date = .distantPast

    init() {
        cache = Self.loadDiskCache()
        if !cache.isEmpty {
            publish(from: Array(cache.values).filter { FileManager.default.fileExists(atPath: $0.path) })
        }
        refresh()
    }

    // MARK: - 扫描

    // 后台增量扫描；2 秒防抖 + 并发去重，widget onAppear 高频触发也不抖。
    func refresh(force: Bool = false) {
        guard !isScanning else { return }
        guard force || Date().timeIntervalSince(lastScanAt) > 2 else { return }
        lastScanAt = Date()
        isScanning = true
        let snapshot = cache
        Task.detached(priority: .userInitiated) {
            let (summaries, newCache) = Self.scan(cache: snapshot)
            Self.saveDiskCache(newCache)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.cache = newCache
                self.publish(from: summaries)
                self.isScanning = false
            }
        }
    }

    private func publish(from summaries: [SessionSummary]) {
        var byCwd: [String: [SessionSummary]] = [:]
        for s in summaries { byCwd[s.cwd, default: []].append(s) }
        var built: [SessionGroup] = byCwd.map { cwd, items in
            let sorted = items.sorted { $0.mtime > $1.mtime }
            let name = (cwd as NSString).lastPathComponent
            return SessionGroup(cwd: cwd, name: name.isEmpty ? cwd : name,
                                sessions: sorted, latest: sorted[0].mtime)
        }
        built.sort { $0.latest > $1.latest }
        groups = built
        totalCount = summaries.count
        recentSessions = Array(summaries.sorted { $0.mtime > $1.mtime }.prefix(4))
    }

    nonisolated private static func scan(cache: [String: SessionSummary]) -> ([SessionSummary], [String: SessionSummary]) {
        let fm = FileManager.default
        var summaries: [SessionSummary] = []
        var newCache: [String: SessionSummary] = [:]
        let dirs = (try? fm.contentsOfDirectory(at: projectsDir, includingPropertiesForKeys: nil)) ?? []
        for dir in dirs {
            let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            for file in files where file.pathExtension == "jsonl" {
                guard let mtime = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))
                    .flatMap(\.contentModificationDate) else { continue }
                let key = file.path
                let summary: SessionSummary
                if let cached = cache[key], abs(cached.mtime.timeIntervalSince(mtime)) < 0.001 {
                    summary = cached
                } else {
                    summary = parseSession(at: file, mtime: mtime)
                }
                newCache[key] = summary
                summaries.append(summary)
            }
        }
        return (summaries, newCache)
    }

    // MARK: - 解析（移植 ccsm.py parse_session）

    nonisolated private static let metaPrefixes = ["<local-command", "<command-name", "<command-message", "<bash-"]

    nonisolated static func parseSession(at url: URL, mtime: Date) -> SessionSummary {
        var title: String?
        var firstMsg: String?
        var cwd: String?
        var branch: String?
        var userCt = 0
        var asstCt = 0

        if let data = fm_read(url) {
            var start = data.startIndex
            let newline = UInt8(ascii: "\n")
            while start < data.endIndex {
                let end = data[start...].firstIndex(of: newline) ?? data.endIndex
                let lineData = data[start..<end]
                start = end < data.endIndex ? data.index(after: end) : data.endIndex
                guard !lineData.isEmpty else { continue }

                // 廉价子串计数，元数据齐了之后也继续（与 ccsm 一致）。
                if lineData.contains(sub: typeUserBytes) {
                    userCt += 1
                } else if lineData.contains(sub: typeAssistantBytes) {
                    asstCt += 1
                }

                let need = title == nil || cwd == nil || firstMsg == nil
                guard need else { continue }
                // 超大行（base64 图片附件）跳过 JSON 解析以保证速度。
                guard lineData.count <= 200_000 else { continue }
                guard lineData.contains(sub: aiTitleBytes) || lineData.contains(sub: typeUserBytes) else { continue }
                guard let obj = try? JSONSerialization.jsonObject(with: Data(lineData)) as? [String: Any] else { continue }

                if title == nil, obj["type"] as? String == "ai-title" {
                    title = obj["aiTitle"] as? String
                    continue
                }
                if obj["type"] as? String == "user" {
                    if cwd == nil, let c = obj["cwd"] as? String, !c.isEmpty { cwd = c }
                    if branch == nil, let b = obj["gitBranch"] as? String, !b.isEmpty { branch = b }
                    if firstMsg == nil {
                        let text = extractText((obj["message"] as? [String: Any])?["content"])
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        if !text.isEmpty, !metaPrefixes.contains(where: text.hasPrefix) {
                            firstMsg = String(text.prefix(200))
                        }
                    }
                }
            }
        }

        // 兜底：从目录名反解（有损，仅供显示）。
        let fallbackCwd = "/" + url.deletingLastPathComponent().lastPathComponent
            .drop(while: { $0 == "-" })
            .replacingOccurrences(of: "-", with: "/")

        return SessionSummary(
            id: url.deletingPathExtension().lastPathComponent,
            path: url.path,
            title: title ?? firstMsg.map { String($0.prefix(60)) } ?? "(无标题)",
            firstMessage: firstMsg ?? "",
            cwd: cwd ?? fallbackCwd,
            branch: branch ?? "",
            messageCount: userCt + asstCt,
            mtime: mtime
        )
    }

    nonisolated private static let typeUserBytes = Array(#""type":"user""#.utf8)
    nonisolated private static let typeAssistantBytes = Array(#""type":"assistant""#.utf8)
    nonisolated private static let aiTitleBytes = Array("ai-title".utf8)

    nonisolated private static func fm_read(_ url: URL) -> Data? {
        try? Data(contentsOf: url, options: .mappedIfSafe)
    }

    // message.content 可能是字符串或 [{type:text,text:..}, ...]。
    nonisolated private static func extractText(_ content: Any?) -> String {
        if let str = content as? String { return str }
        guard let blocks = content as? [Any] else { return "" }
        var parts: [String] = []
        for block in blocks {
            if let dict = block as? [String: Any],
               dict["type"] as? String == "text",
               let text = dict["text"] as? String {
                parts.append(text)
            }
        }
        return parts.joined(separator: " ")
    }

    // MARK: - 磁盘缓存

    nonisolated private static func loadDiskCache() -> [String: SessionSummary] {
        guard let data = try? Data(contentsOf: cacheURL),
              let cache = try? JSONDecoder().decode([String: SessionSummary].self, from: data) else { return [:] }
        return cache
    }

    nonisolated private static func saveDiskCache(_ cache: [String: SessionSummary]) {
        let dir = cacheURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: cacheURL, options: .atomic)
    }

    // MARK: - 全文搜索

    // 返回命中的 jsonl path 集合；查询为空返回 nil（= 不过滤）。
    func fullTextSearch(_ query: String) async -> Set<String>? {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return nil }
        let paths = groups.flatMap { $0.sessions.map(\.path) }
        return await Task.detached(priority: .userInitiated) {
            if let hits = Self.ripgrepSearch(q) { return hits }
            return Self.swiftSearch(q, paths: paths)
        }.value
    }

    // GUI 进程 PATH 很窄且 rg 可能只是 shell 函数，只认这几处真实二进制。
    nonisolated private static let rgCandidates = ["/opt/homebrew/bin/rg", "/usr/local/bin/rg", "/usr/bin/rg"]

    nonisolated private static func ripgrepSearch(_ query: String) -> Set<String>? {
        guard let rg = rgCandidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            return nil
        }
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: rg)
        process.arguments = ["-l", "-i", "--", query, projectsDir.path]
        process.standardOutput = pipe
        process.standardError = Pipe()
        do { try process.run() } catch { return nil }

        let deadline = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 20, execute: deadline)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        deadline.cancel()

        switch process.terminationStatus {
        case 0:
            let lines = String(decoding: data, as: UTF8.self).split(separator: "\n")
            return Set(lines.map(String.init).filter { $0.hasSuffix(".jsonl") })
        case 1:
            return []   // rg 约定：无命中
        default:
            return nil  // 出错，走 Swift 兜底
        }
    }

    // 纯 Swift 兜底：按文件整体做大小写不敏感匹配，20s 时限内返回已得结果。
    nonisolated private static func swiftSearch(_ query: String, paths: [String]) -> Set<String> {
        var hits: Set<String> = []
        let deadline = Date().addingTimeInterval(20)
        for path in paths {
            if Task.isCancelled || Date() > deadline { break }
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe) else { continue }
            let text = String(decoding: data, as: UTF8.self)
            if text.range(of: query, options: .caseInsensitive) != nil {
                hits.insert(path)
            }
        }
        return hits
    }

    // MARK: - Resume

    // 在所选终端新窗口 cd 到项目并 claude --resume。
    @discardableResult
    func resume(_ session: SessionSummary, skipPermissions: Bool) -> Bool {
        let flag = skipPermissions ? " --dangerously-skip-permissions" : ""
        let cmd = "cd \(Self.shellQuote(session.cwd)) && claude --resume \(Self.shellQuote(session.id))\(flag)"
        let ok = Self.preferredTerminal.launch(command: cmd)
        if ok {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.refresh(force: true)
            }
        }
        return ok
    }

    // shlex.quote 等价物：安全字符原样，否则单引号包裹。
    nonisolated static func shellQuote(_ s: String) -> String {
        if !s.isEmpty, s.range(of: "^[A-Za-z0-9_@%+=:,./-]+$", options: .regularExpression) != nil {
            return s
        }
        return "'" + s.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    // MARK: - 项目强调色

    // cwd 哈希出稳定色相：同一项目永远同色，扫一眼即可区分。
    // 文字用粉彩（低饱和、全亮度）：蓝紫等暗色相在玻璃上也保持可读。
    nonisolated static func projectColor(_ cwd: String) -> Color {
        Color(hue: projectHue(cwd), saturation: 0.4, brightness: 1.0)
    }

    nonisolated private static func projectHue(_ cwd: String) -> Double {
        var hash: UInt64 = 5381
        for byte in cwd.utf8 { hash = hash &* 33 &+ UInt64(byte) }
        return Double(hash % 360) / 360
    }

    // MARK: - 时间显示

    nonisolated static func timeAgo(_ date: Date) -> String {
        let s = Date().timeIntervalSince(date)
        if s < 60 { return "刚刚" }
        if s < 3600 { return "\(Int(s / 60))分钟前" }
        if s < 86400 { return "\(Int(s / 3600))小时前" }
        if s < 2_592_000 { return "\(Int(s / 86400))天前" }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-M-d"
        return fmt.string(from: date)
    }
}

// Resume 支持的终端及各自的启动方言。
// 未适配：Warp（无可运行命令的自动化接口）、Hyper/Tabby（Electron 无接口）。
enum ResumeTerminal: String, CaseIterable {
    case terminal = "Terminal"
    case otty = "Otty"
    case iterm = "iTerm"
    case ghostty = "Ghostty"
    case kitty = "kitty"
    case alacritty = "Alacritty"
    case wezterm = "WezTerm"

    var displayName: String {
        self == .iterm ? "iTerm2" : rawValue
    }

    var isInstalled: Bool {
        if self == .terminal { return true }
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        return fm.fileExists(atPath: "/Applications/\(rawValue).app")
            || fm.fileExists(atPath: "\(home)/Applications/\(rawValue).app")
    }

    // 在新窗口执行 cmd（形如 `cd '…' && claude --resume '…'`）。
    func launch(command cmd: String) -> Bool {
        switch self {
        case .terminal, .otty:
            // Otty 的 AppleScript 字典按 Terminal.app 兼容设计，同一份脚本换 app 名即可。
            return runAppleScript("""
            tell application "\(rawValue)" to activate
            tell application "\(rawValue)" to do script "\(Self.appleScriptEscape(cmd))"
            """)
        case .iterm:
            return runAppleScript("""
            tell application "iTerm"
                activate
                set newWindow to (create window with default profile)
                tell current session of newWindow to write text "\(Self.appleScriptEscape(cmd))"
            end tell
            """)
        case .ghostty:
            // 无 AppleScript：CLI 直接带命令启动。命令不经 do script 打进交互 shell，
            // 必须包一层 zsh -ic 加载用户 rc，否则 GUI 进程的窄 PATH 找不到 claude。
            return openApp(args: ["-e", "zsh", "-ic", cmd])
        case .kitty:
            return openApp(args: ["--hold", "zsh", "-ic", cmd])
        case .alacritty:
            return openApp(args: ["--hold", "-e", "zsh", "-ic", cmd])
        case .wezterm:
            return openApp(args: ["start", "--", "zsh", "-ic", cmd])
        }
    }

    // AppleScript 字符串字面量转义（shellQuote 只产单引号，防御性处理 \ 和 "）。
    private static func appleScriptEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func runAppleScript(_ source: String) -> Bool {
        guard let script = NSAppleScript(source: source) else { return false }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        return error == nil
    }

    // `open -na <App> --args …`：参数按数组直传，不经过 shell，无引号问题。
    private func openApp(args: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-na", rawValue, "--args"] + args
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do { try process.run() } catch { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }
}

private extension Data.SubSequence {
    // 朴素子串搜索；行短模式短，够快。
    func contains(sub: [UInt8]) -> Bool {
        guard !sub.isEmpty, count >= sub.count else { return false }
        let first = sub[0]
        var i = startIndex
        let limit = index(endIndex, offsetBy: -(sub.count - 1))
        while i < limit {
            if self[i] == first {
                var match = true
                var j = index(after: i)
                for k in 1..<sub.count {
                    if self[j] != sub[k] { match = false; break }
                    j = index(after: j)
                }
                if match { return true }
            }
            i = index(after: i)
        }
        return false
    }
}
