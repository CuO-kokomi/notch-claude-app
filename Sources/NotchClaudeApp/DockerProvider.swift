import Foundation

@MainActor
final class DockerProvider: ObservableObject {
    struct Container: Identifiable {
        let id: String
        let name: String
        let status: String
        let isRunning: Bool
    }

    @Published private(set) var containers: [Container] = []
    @Published private(set) var isDockerRunning = false

    private var timer: Timer?

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.refresh()
        }
    }

    private func refresh() {
        let output = run("/usr/local/bin/docker", args: ["ps", "-a", "--format", "{{.ID}}|{{.Names}}|{{.Status}}|{{.State}}"])
        if output.isEmpty {
            let altOutput = run("/opt/homebrew/bin/docker", args: ["ps", "-a", "--format", "{{.ID}}|{{.Names}}|{{.Status}}|{{.State}}"])
            if altOutput.isEmpty {
                isDockerRunning = false
                containers = []
                return
            }
            parseOutput(altOutput)
        } else {
            parseOutput(output)
        }
    }

    private func parseOutput(_ output: String) {
        isDockerRunning = true
        let lines = output.components(separatedBy: "\n").filter { !$0.isEmpty }
        containers = lines.prefix(6).compactMap { line in
            let parts = line.split(separator: "|", omittingEmptySubsequences: false)
            guard parts.count >= 4 else { return nil }
            return Container(
                id: String(parts[0]),
                name: String(parts[1]),
                status: String(parts[2]),
                isRunning: parts[3] == "running"
            )
        }
    }

    private func run(_ command: String, args: [String]) -> String {
        guard FileManager.default.fileExists(atPath: command) else { return "" }
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = args
        process.standardOutput = pipe
        process.standardError = Pipe()
        try? process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
