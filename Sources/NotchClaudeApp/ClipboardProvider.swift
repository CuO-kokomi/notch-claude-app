import Foundation
import AppKit

@MainActor
final class ClipboardProvider: ObservableObject {
    struct ClipItem: Identifiable {
        let id = UUID()
        let text: String
        let timestamp: Date
    }

    @Published private(set) var items: [ClipItem] = []

    private var timer: Timer?
    private var lastChangeCount: Int

    init() {
        lastChangeCount = NSPasteboard.general.changeCount
        if let current = NSPasteboard.general.string(forType: .string), !current.isEmpty {
            items.append(ClipItem(text: current, timestamp: Date()))
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkClipboard() }
        }
    }

    private func checkClipboard() {
        let currentCount = NSPasteboard.general.changeCount
        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else { return }
        if items.first?.text == text { return }
        items.insert(ClipItem(text: text, timestamp: Date()), at: 0)
        if items.count > 5 { items = Array(items.prefix(5)) }
    }

    func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        lastChangeCount = NSPasteboard.general.changeCount
    }
}
