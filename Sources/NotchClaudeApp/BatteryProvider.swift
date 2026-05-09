import Foundation
import IOKit.ps

@MainActor
final class BatteryProvider: ObservableObject {
    @Published private(set) var percentage: Int = -1
    @Published private(set) var isCharging = false
    @Published private(set) var timeRemaining = ""

    private var timer: Timer?

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    private func refresh() {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [Any],
              let first = sources.first,
              let desc = IOPSGetPowerSourceDescription(snapshot, first as CFTypeRef)?.takeUnretainedValue() as? [String: Any] else {
            percentage = -1
            return
        }

        percentage = desc[kIOPSCurrentCapacityKey] as? Int ?? -1
        isCharging = (desc[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue

        if let minutes = desc[kIOPSTimeToEmptyKey] as? Int, minutes > 0, !isCharging {
            let h = minutes / 60
            let m = minutes % 60
            timeRemaining = h > 0 ? "\(h)h\(m)m" : "\(m)m"
        } else if let minutes = desc[kIOPSTimeToFullChargeKey] as? Int, minutes > 0, isCharging {
            let h = minutes / 60
            let m = minutes % 60
            timeRemaining = h > 0 ? "\(h)h\(m)m 充满" : "\(m)m 充满"
        } else {
            timeRemaining = ""
        }
    }
}
