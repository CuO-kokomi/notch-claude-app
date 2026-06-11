import Foundation

// 解析 Claude Code transcript（JSONL）尾部，提取任务交回时刻需要的三样信息：
// 当轮 API 错误、最后一条回复摘要、上下文窗口用量。只在会话跃迁到 waiting 时调用一次。
enum TranscriptParser {
    struct Result {
        var apiError: String?
        var lastAssistantText: String?
        // 上下文用量 tokens；窗口大小 hook 拿不到，只能给出"是否像 1M 窗口"的推断。
        var contextUsedTokens: Int?
        var contextInferred1M = false
    }

    // 只读尾部 256KB：transcript 可能很大，且需要的信息都在最近几条。
    private static let tailBytes = 256 * 1024
    private static let resultMaxLength = 300

    static func parse(path: String, sessionId: String) -> Result {
        let entries = tailEntries(path: path)
        guard !entries.isEmpty else { return Result() }
        let usage = contextUsage(entries: entries, sessionId: sessionId)
        return Result(
            apiError: currentTurnApiError(entries: entries, sessionId: sessionId),
            lastAssistantText: lastAssistantText(entries: entries, sessionId: sessionId),
            contextUsedTokens: usage?.used,
            contextInferred1M: usage?.inferred1M ?? false
        )
    }

    // MARK: - JSONL 尾部读取

    private static func tailEntries(path: String) -> [[String: Any]] {
        guard let handle = FileHandle(forReadingAtPath: path) else { return [] }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd(), size > 0 else { return [] }

        let readLength = min(Int(size), tailBytes)
        let truncated = Int(size) > readLength
        try? handle.seek(toOffset: UInt64(Int(size) - readLength))
        guard let data = try? handle.read(upToCount: readLength),
              let text = String(data: data, encoding: .utf8) else { return [] }

        var lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        // 尾部截断读取时第一行多半是被切坏的半行，丢弃。
        if truncated && !lines.isEmpty { lines.removeFirst() }

        var entries: [[String: Any]] = []
        entries.reserveCapacity(lines.count)
        for line in lines {
            guard let lineData = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else { continue }
            entries.append(obj)
        }
        return entries
    }

    // MARK: - 条目判定

    private static func matchesSession(_ entry: [String: Any], _ sessionId: String) -> Bool {
        guard let sid = entry["sessionId"] as? String else { return true }
        return sid == sessionId
    }

    private static func isSubagent(_ entry: [String: Any]) -> Bool {
        for key in ["isSidechain", "isSubagent", "is_subagent", "subagent"] {
            if entry[key] as? Bool == true { return true }
        }
        return false
    }

    // MARK: - 当轮 API 错误

    // Claude Code 把 API 错误合成为 isApiErrorMessage:true 的假 assistant 条目并发普通 Stop。
    // 只认"当轮"错误：错误之后出现 user 条目（用户重新输入）或正常 assistant 条目（已恢复）即视为过期。
    private static func currentTurnApiError(entries: [[String: Any]], sessionId: String) -> String? {
        var errorIndex: Int?
        for i in stride(from: entries.count - 1, through: 0, by: -1) {
            let entry = entries[i]
            guard entry["isApiErrorMessage"] as? Bool == true,
                  entry["sessionId"] as? String == sessionId else { continue }
            errorIndex = i
            break
        }
        guard let errorIndex else { return nil }

        for i in (errorIndex + 1)..<entries.count {
            let type = entries[i]["type"] as? String ?? ""
            if type == "user" { return nil }
            if type == "assistant" && entries[i]["isApiErrorMessage"] as? Bool != true { return nil }
        }
        return entries[errorIndex]["error"] as? String ?? "unknown"
    }

    // MARK: - 最后一条回复

    private static func lastAssistantText(entries: [[String: Any]], sessionId: String) -> String? {
        for entry in entries.reversed() {
            let type = entry["type"] as? String ?? ""
            // 撞到本会话的 user 条目说明已越过本轮边界。
            if type == "user" && matchesSession(entry, sessionId) { return nil }
            guard type == "assistant",
                  entry["isApiErrorMessage"] as? Bool != true,
                  matchesSession(entry, sessionId),
                  !isSubagent(entry) else { continue }
            let text = assistantText(from: entry)
            if !text.isEmpty { return clamp(text) }
        }
        return nil
    }

    private static func assistantText(from entry: [String: Any]) -> String {
        let content = (entry["message"] as? [String: Any])?["content"] ?? entry["content"] as Any
        var parts: [String] = []
        if let str = content as? String {
            parts.append(str)
        } else if let blocks = content as? [Any] {
            for block in blocks {
                if let str = block as? String {
                    parts.append(str)
                } else if let dict = block as? [String: Any],
                          let type = dict["type"] as? String,
                          type == "text" || type == "output_text",
                          let text = dict["text"] as? String {
                    parts.append(text)
                }
            }
        }
        return normalize(parts.joined(separator: "\n"))
    }

    private static func normalize(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: .controlCharacters.subtracting(.newlines))
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func clamp(_ text: String) -> String {
        guard text.count > resultMaxLength else { return text }
        return String(text.prefix(resultMaxLength - 1)) + "…"
    }

    // MARK: - 上下文用量

    // 当前用量取最近一条有效 assistant 条目；1M 推断：模型名带 "1m"，
    // 或本会话用量水位曾超过 200k（200k 窗口在 ~92% 就会自动压缩，超过即说明是 1M）。
    private static func contextUsage(entries: [[String: Any]], sessionId: String) -> (used: Int, inferred1M: Bool)? {
        var current: Int?
        var watermark = 0
        var modelHints1M = false
        for entry in entries.reversed() {
            guard entry["type"] as? String == "assistant",
                  entry["isApiErrorMessage"] as? Bool != true,
                  matchesSession(entry, sessionId),
                  !isSubagent(entry),
                  let message = entry["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any] else { continue }

            let used = intValue(usage["input_tokens"])
                + intValue(usage["cache_read_input_tokens"])
                + intValue(usage["cache_creation_input_tokens"])
            guard used > 0 else { continue }

            if current == nil { current = used }
            watermark = max(watermark, used)
            if (message["model"] as? String ?? "").lowercased().contains("1m") {
                modelHints1M = true
            }
        }
        guard let current else { return nil }
        return (current, modelHints1M || watermark > 200_000)
    }

    private static func intValue(_ value: Any?) -> Int {
        if let n = value as? Int { return n }
        if let n = value as? Double { return Int(n) }
        return 0
    }
}
