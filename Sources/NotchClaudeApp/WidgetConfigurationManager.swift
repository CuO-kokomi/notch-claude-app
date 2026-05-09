import SwiftUI

@MainActor
final class WidgetConfigurationManager: ObservableObject {
    @Published var activeWidgetIDs: [String] {
        didSet { save() }
    }

    static let minWidgets = 2
    static let maxWidgets = 6

    private let key = "activeWidgetIDs"
    private let defaultIDs = ["claude_status", "calendar", "timer", "system_stats"]

    init() {
        if let saved = UserDefaults.standard.stringArray(forKey: key), !saved.isEmpty {
            activeWidgetIDs = saved.filter { id in
                WidgetRegistry.all.contains { $0.id == id }
            }
        } else {
            activeWidgetIDs = defaultIDs
        }
    }

    var activeDescriptors: [WidgetDescriptor] {
        activeWidgetIDs.compactMap { WidgetRegistry.descriptor(for: $0) }
    }

    var inactiveDescriptors: [WidgetDescriptor] {
        WidgetRegistry.all.filter { desc in !activeWidgetIDs.contains(desc.id) }
    }

    var widgetCount: Int { activeWidgetIDs.count }

    func move(fromOffsets: IndexSet, toOffset: Int) {
        activeWidgetIDs.move(fromOffsets: fromOffsets, toOffset: toOffset)
    }

    func add(_ id: String) {
        guard activeWidgetIDs.count < Self.maxWidgets,
              !activeWidgetIDs.contains(id) else { return }
        activeWidgetIDs.append(id)
    }

    func remove(_ id: String) {
        guard activeWidgetIDs.count > Self.minWidgets else { return }
        activeWidgetIDs.removeAll { $0 == id }
    }

    private func save() {
        UserDefaults.standard.set(activeWidgetIDs, forKey: key)
    }
}
