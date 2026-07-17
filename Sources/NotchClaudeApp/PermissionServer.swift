import Foundation
import Network

// 来自 Claude Code 的一次待审批权限请求（HTTP PermissionRequest hook，连接挂起等待答复）。
struct PermissionRequest: Identifiable {
    let id: UUID
    let toolName: String
    let detail: String?
    let receivedAt: Date
    // 所属会话，用于识别"用户已在终端处理过"的过期请求。
    let sessionId: String?
    // Claude Code 附带的"始终允许"规则建议（addRules），原样回传 updatedPermissions 即可生效。
    let alwaysAllowSuggestion: [String: Any]?
}

enum PermissionDecision {
    case allow
    case alwaysAllow
    case deny
}

// 本地 HTTP 服务：Claude Code 的 PermissionRequest hook POST 到这里并阻塞等答复，
// 用户在刘海上点 允许/拒绝 后才返回决定。app 未运行时连接被拒，Claude Code 回退终端确认。
@MainActor
final class PermissionServer: ObservableObject {
    // 必须与 install-claude-hooks.sh 写入 settings.json 的 PERMISSION_URL 端口一致。
    nonisolated static let port: UInt16 = 23889

    // 让用户做多选/选项的工具：刘海的允许/拒绝二元按钮表达不了，交回终端选项菜单。
    nonisolated static let choiceTools: Set<String> = ["AskUserQuestion"]

    // 待审批请求，按到达顺序排队；UI 显示第一个。
    @Published private(set) var pending: [PermissionRequest] = []
    // 新请求到达回调（用于发系统通知）。
    var onNewRequest: ((PermissionRequest) -> Void)?

    private var listener: NWListener?
    // 挂起中的连接，key 与 PermissionRequest.id 相同。
    private var connections: [UUID: NWConnection] = [:]

    init() { start() }

    private func start() {
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            // 只收本机回环连接，权限决定不暴露给局域网。
            params.requiredInterfaceType = .loopback
            let listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: Self.port)!)
            listener.newConnectionHandler = { conn in
                Task { @MainActor [weak self] in self?.accept(conn) }
            }
            listener.start(queue: .main)
            self.listener = listener
        } catch {
            // 端口被占（如另一份实例）：审批功能降级，Claude Code 走终端确认，其余功能不受影响。
            NSLog("PermissionServer: 监听 127.0.0.1:%d 失败，刘海审批不可用：%@", Int(Self.port), "\(error)")
        }
    }

    // MARK: - 连接处理

    private func accept(_ conn: NWConnection) {
        let connID = UUID()
        conn.stateUpdateHandler = { state in
            switch state {
            case .failed, .cancelled:
                Task { @MainActor [weak self] in self?.drop(connID) }
            default:
                break
            }
        }
        conn.start(queue: .main)
        receiveRequest(on: conn, connID: connID, buffer: Data())
    }

    private func receiveRequest(on conn: NWConnection, connID: UUID, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, isComplete, error in
            Task { @MainActor [weak self] in
                guard let self else { conn.cancel(); return }
                var buf = buffer
                if let data { buf.append(data) }
                if let request = Self.parseHTTPRequest(buf) {
                    self.handle(request, conn: conn, connID: connID)
                    return
                }
                if isComplete || error != nil || buf.count > 512 * 1024 {
                    conn.cancel()
                    return
                }
                self.receiveRequest(on: conn, connID: connID, buffer: buf)
            }
        }
    }

    private func handle(_ request: HTTPRequest, conn: NWConnection, connID: UUID) {
        guard request.method == "POST", request.path.hasPrefix("/permission") else {
            Self.send(conn, status: "404 Not Found", body: Data())
            return
        }
        guard let payload = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any],
              let toolName = payload["tool_name"] as? String else {
            // 看不懂的请求体：回 204 让 Claude Code 走自己的确认流程。
            Self.send(conn, status: "204 No Content", body: Data())
            return
        }
        // 选择题类工具（AskUserQuestion 让用户选选项，不是同意/拒绝）不适合刘海的二元按钮，
        // 直接回 204 让 Claude Code 用终端的选项菜单处理。
        if Self.choiceTools.contains(toolName) {
            Self.send(conn, status: "204 No Content", body: Data())
            return
        }

        let input = payload["tool_input"] as? [String: Any] ?? [:]
        let item = PermissionRequest(
            id: connID,
            toolName: toolName,
            detail: Self.extractDetail(toolName: toolName, input: input),
            receivedAt: Date(),
            sessionId: payload["session_id"] as? String,
            alwaysAllowSuggestion: Self.extractAlwaysAllowSuggestion(payload)
        )
        connections[connID] = conn
        pending.append(item)
        onNewRequest?(item)
        // 继续监听：对端提前关闭（用户在终端先回答 / 请求取消）就撤掉审批卡。
        watchForClose(on: conn, connID: connID)
    }

    private func watchForClose(on conn: NWConnection, connID: UUID) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 4096) { _, _, isComplete, error in
            Task { @MainActor [weak self] in
                guard let self, self.connections[connID] != nil else { return }
                if isComplete || error != nil {
                    conn.cancel()
                    self.drop(connID)
                    return
                }
                self.watchForClose(on: conn, connID: connID)
            }
        }
    }

    private func drop(_ connID: UUID) {
        connections.removeValue(forKey: connID)
        pending.removeAll { $0.id == connID }
    }

    // 兜底撤卡：用户在终端先回答时，新版 Claude Code 不再断开挂起的 hook 连接
    //（watchForClose 等不到关闭信号），但我们自己的状态 hook 会继续推进会话——
    // 批准 → PreToolUse 写 running；拒绝 → 后续事件推进。只要请求所属会话的状态
    // 在请求之后被更新、且不再是 allow，即视为已在别处处理，回 204 撤卡。
    // 边界：同会话并行工具的 PreToolUse 也可能触发误撤，此时终端提示仍在，无害。
    func dismissHandledElsewhere(sessions: [ClaudeSession]) {
        guard !pending.isEmpty else { return }
        for request in pending {
            guard let sid = request.sessionId,
                  let session = sessions.first(where: { $0.id == sid }),
                  session.status != .allow,
                  let updated = session.updatedAt,
                  updated > request.receivedAt.addingTimeInterval(0.5) else { continue }
            if let conn = connections.removeValue(forKey: request.id) {
                // 204 = 无决定，Claude Code 若还在等会走自己的流程；已处理则忽略。
                Self.send(conn, status: "204 No Content", body: Data())
            }
            pending.removeAll { $0.id == request.id }
        }
    }

    // MARK: - 用户决定

    func respond(_ id: UUID, decision: PermissionDecision) {
        guard let conn = connections.removeValue(forKey: id) else { return }
        let request = pending.first { $0.id == id }
        pending.removeAll { $0.id == id }

        var decisionObj: [String: Any]
        switch decision {
        case .allow:
            decisionObj = ["behavior": "allow"]
        case .alwaysAllow:
            decisionObj = ["behavior": "allow"]
            // 回传 Claude Code 自己建议的 addRules 规则，等同终端里的 "Always allow"。
            if let suggestion = request?.alwaysAllowSuggestion {
                decisionObj["updatedPermissions"] = [suggestion]
            }
        case .deny:
            decisionObj = ["behavior": "deny", "message": "在灵动岛上被拒绝"]
        }
        let bodyObj: [String: Any] = [
            "hookSpecificOutput": [
                "hookEventName": "PermissionRequest",
                "decision": decisionObj,
            ]
        ]
        let body = (try? JSONSerialization.data(withJSONObject: bodyObj)) ?? Data()
        Self.send(conn, status: "200 OK", body: body)
    }

    // MARK: - HTTP 极简实现（单个 POST，不支持 keep-alive）

    private struct HTTPRequest {
        let method: String
        let path: String
        let body: Data
    }

    private nonisolated static func parseHTTPRequest(_ data: Data) -> HTTPRequest? {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        guard let head = String(data: data[..<headerEnd.lowerBound], encoding: .utf8) else { return nil }
        let lines = head.components(separatedBy: "\r\n")
        let requestParts = lines.first?.split(separator: " ") ?? []
        guard requestParts.count >= 2 else { return nil }

        var contentLength = 0
        for line in lines.dropFirst() {
            let pair = line.split(separator: ":", maxSplits: 1)
            if pair.count == 2, pair[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length" {
                contentLength = Int(pair[1].trimmingCharacters(in: .whitespaces)) ?? 0
            }
        }
        let body = data[headerEnd.upperBound...]
        guard body.count >= contentLength else { return nil }
        return HTTPRequest(
            method: String(requestParts[0]),
            path: String(requestParts[1]),
            body: Data(body.prefix(contentLength))
        )
    }

    private nonisolated static func send(_ conn: NWConnection, status: String, body: Data) {
        var head = "HTTP/1.1 \(status)\r\n"
        if !body.isEmpty {
            head += "Content-Type: application/json\r\n"
        }
        head += "Content-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        var data = Data(head.utf8)
        data.append(body)
        conn.send(content: data, completion: .contentProcessed { _ in conn.cancel() })
    }

    // 取 Claude Code 建议作为"始终允许"的来源：优先 allow 方向的 addRules（写权限规则）；
    // 文件类工具（Write/Edit）只给 setMode(acceptEdits)，也接受——等价于会话内自动接受编辑。
    private nonisolated static func extractAlwaysAllowSuggestion(_ payload: [String: Any]) -> [String: Any]? {
        let suggestions = payload["permission_suggestions"] as? [[String: Any]] ?? []
        let candidate = suggestions.first(where: { s in
            (s["type"] as? String) == "addRules"
                && ((s["behavior"] as? String) ?? "allow") == "allow"
        }) ?? suggestions.first(where: { ($0["type"] as? String) == "setMode" })
        guard var suggestion = candidate else { return nil }
        if suggestion["destination"] == nil { suggestion["destination"] = "localSettings" }
        if (suggestion["type"] as? String) == "addRules", suggestion["behavior"] == nil {
            suggestion["behavior"] = "allow"
        }
        return suggestion
    }

    // 与 hook 脚本相同的"工具 → 关键参数"摘要规则。
    private nonisolated static func extractDetail(toolName: String, input: [String: Any]) -> String? {
        func str(_ key: String) -> String? { input[key] as? String }
        let raw: String?
        switch toolName {
        case "Bash":
            raw = str("command")
        case "Edit", "MultiEdit", "Write", "Read":
            raw = str("file_path").map { URL(fileURLWithPath: $0).lastPathComponent }
        case "NotebookEdit":
            raw = str("notebook_path").map { URL(fileURLWithPath: $0).lastPathComponent }
        case "Task", "Agent":
            raw = str("subagent_type") ?? str("description")
        case "WebFetch", "WebSearch":
            raw = str("url") ?? str("query")
        default:
            raw = input.values.compactMap { $0 as? String }.first
        }
        guard var text = raw?
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !text.isEmpty else { return nil }
        if text.count > 200 {
            text = String(text.prefix(199)) + "…"
        }
        return text
    }
}
