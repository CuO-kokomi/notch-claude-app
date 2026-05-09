import Foundation
import AppKit

@MainActor
final class GitStatusProvider: ObservableObject {
    @Published private(set) var branch = ""
    @Published private(set) var uncommittedCount = 0
    @Published private(set) var lastCommitMessage = ""
    @Published private(set) var isGitRepo = false
    @Published private(set) var repoName = ""

    private var timer: Timer?
    private var workingDirectory: String?

    private let savedPathKey = "gitRepoPath"

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            if let saved = UserDefaults.standard.string(forKey: self?.savedPathKey ?? ""),
               !saved.isEmpty {
                self?.workingDirectory = saved
            } else {
                self?.workingDirectory = self?.findGitDirectory()
            }
            self?.refresh()
        }
    }

    func pickDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "选择一个 Git 仓库目录"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                let path = url.path
                let result = self?.run("git", args: ["-C", path, "rev-parse", "--show-toplevel"]) ?? ""
                if !result.isEmpty {
                    self?.workingDirectory = result
                    UserDefaults.standard.set(result, forKey: self?.savedPathKey ?? "")
                    self?.refresh()
                }
            }
        }
    }

    private func refresh() {
        guard let dir = workingDirectory else {
            isGitRepo = false
            return
        }
        isGitRepo = true
        repoName = URL(fileURLWithPath: dir).lastPathComponent
        branch = run("git", args: ["-C", dir, "rev-parse", "--abbrev-ref", "HEAD"])
        let status = run("git", args: ["-C", dir, "status", "--porcelain"])
        uncommittedCount = status.isEmpty ? 0 : status.components(separatedBy: "\n").filter { !$0.isEmpty }.count
        lastCommitMessage = run("git", args: ["-C", dir, "log", "-1", "--pretty=%s"])
    }

    private func findGitDirectory() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let fm = FileManager.default

        var candidates: [String] = []
        let searchDirs = [home + "/Desktop", home + "/Documents", home + "/Projects", home + "/Developer", home + "/Code", home]
        for dir in searchDirs {
            guard fm.fileExists(atPath: dir) else { continue }
            let result = run("git", args: ["-C", dir, "rev-parse", "--show-toplevel"])
            if !result.isEmpty {
                candidates.append(result)
            }
        }

        if candidates.isEmpty {
            if let contents = try? fm.contentsOfDirectory(atPath: home) {
                for item in contents.prefix(20) {
                    let path = home + "/" + item
                    var isDir: ObjCBool = false
                    guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { continue }
                    if fm.fileExists(atPath: path + "/.git") {
                        candidates.append(path)
                        break
                    }
                }
            }
        }

        return candidates.first
    }

    private func run(_ command: String, args: [String]) -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/\(command)")
        process.arguments = args
        process.standardOutput = pipe
        process.standardError = Pipe()
        try? process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
