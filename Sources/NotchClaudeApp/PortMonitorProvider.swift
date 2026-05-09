import Foundation

@MainActor
final class PortMonitorProvider: ObservableObject {
    struct PortInfo: Identifiable {
        let id: Int
        var port: Int { id }
        let process: String
        let isActive: Bool
    }

    @Published private(set) var ports: [PortInfo] = []

    private var timer: Timer?
    private let watchPorts = [3000, 5173, 8080, 8000, 4200, 5000]

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.refresh()
        }
    }

    private func refresh() {
        var results: [PortInfo] = []
        for port in watchPorts {
            let output = run("/usr/sbin/lsof", args: ["-i", ":\(port)", "-sTCP:LISTEN", "-t"])
            if !output.isEmpty {
                let pid = output.components(separatedBy: "\n").first ?? ""
                let processName = pid.isEmpty ? "" : run("/bin/ps", args: ["-p", pid, "-o", "comm="])
                let name = processName.components(separatedBy: "/").last ?? processName
                results.append(PortInfo(id: port, process: name, isActive: true))
            } else {
                results.append(PortInfo(id: port, process: "", isActive: false))
            }
        }
        ports = results
    }

    private func run(_ command: String, args: [String]) -> String {
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
