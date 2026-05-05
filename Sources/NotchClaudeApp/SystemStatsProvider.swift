import Foundation
import MachO
import Darwin

@MainActor
final class SystemStatsProvider: ObservableObject {
    @Published private(set) var cpuText = "--"
    @Published private(set) var memoryText = "--"
    @Published private(set) var uploadText = "--"
    @Published private(set) var downloadText = "--"

    private var timer: Timer?
    private var previousNetworkSample: NetworkSample?

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    private func refresh() {
        cpuText = String(format: "%.0f%%", currentCPUUsage())
        memoryText = currentMemoryText()
        refreshNetworkText()
    }

    private func currentCPUUsage() -> Double {
        // host_processor_info 返回的是启动以来累计 tick，这里只做轻量近似展示。
        var cpuInfo: processor_info_array_t?
        var cpuInfoCount: mach_msg_type_number_t = 0
        var processorCount: natural_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &processorCount,
            &cpuInfo,
            &cpuInfoCount
        )

        guard result == KERN_SUCCESS, let cpuInfo else { return 0 }
        defer {
            let byteCount = vm_size_t(cpuInfoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: cpuInfo), byteCount)
        }

        var totalUsage = 0.0
        let cpuLoadInfoCount = Int(CPU_STATE_MAX)

        for cpu in 0..<Int(processorCount) {
            let offset = cpu * cpuLoadInfoCount
            let user = Double(cpuInfo[offset + Int(CPU_STATE_USER)])
            let system = Double(cpuInfo[offset + Int(CPU_STATE_SYSTEM)])
            let nice = Double(cpuInfo[offset + Int(CPU_STATE_NICE)])
            let idle = Double(cpuInfo[offset + Int(CPU_STATE_IDLE)])
            let total = user + system + nice + idle
            if total > 0 {
                totalUsage += ((total - idle) / total) * 100
            }
        }

        return processorCount == 0 ? 0 : totalUsage / Double(processorCount)
    }

    private func currentMemoryText() -> String {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, reboundPointer, &count)
            }
        }

        guard result == KERN_SUCCESS else { return "--" }

        let pageSize = Double(vm_kernel_page_size)
        // active + wired + compressed 更接近活动占用，避免把文件缓存全部算成已用。
        let active = Double(stats.active_count) * pageSize
        let wired = Double(stats.wire_count) * pageSize
        let compressed = Double(stats.compressor_page_count) * pageSize
        let usedGB = (active + wired + compressed) / 1_073_741_824
        let totalGB = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824

        return String(format: "%.1fG/%.0fG", usedGB, totalGB)
    }

    private func refreshNetworkText() {
        // 网速通过两次网卡累计字节差值估算，第一次采样先显示占位。
        guard let sample = currentNetworkSample() else {
            uploadText = "--"
            downloadText = "--"
            return
        }

        guard let previousSample = previousNetworkSample else {
            previousNetworkSample = sample
            uploadText = "--"
            downloadText = "--"
            return
        }

        let interval = sample.timestamp.timeIntervalSince(previousSample.timestamp)
        guard interval > 0 else { return }

        // 使用 Int64 防止计数器重置时 UInt64 减法溢出
        let sentDelta = max(0, Int64(sample.sentBytes) - Int64(previousSample.sentBytes))
        let receivedDelta = max(0, Int64(sample.receivedBytes) - Int64(previousSample.receivedBytes))
        uploadText = formatBytesPerSecond(Double(sentDelta) / interval)
        downloadText = formatBytesPerSecond(Double(receivedDelta) / interval)
        previousNetworkSample = sample
    }

    private func currentNetworkSample() -> NetworkSample? {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let firstAddress = addresses else { return nil }
        defer { freeifaddrs(addresses) }

        var sentBytes: UInt64 = 0
        var receivedBytes: UInt64 = 0
        var pointer: UnsafeMutablePointer<ifaddrs>? = firstAddress

        while let interface = pointer?.pointee {
            defer { pointer = interface.ifa_next }
            guard interface.ifa_addr.pointee.sa_family == UInt8(AF_LINK),
                  (interface.ifa_flags & UInt32(IFF_UP)) != 0,
                  (interface.ifa_flags & UInt32(IFF_LOOPBACK)) == 0,
                  let data = interface.ifa_data?.assumingMemoryBound(to: if_data.self).pointee else {
                continue
            }
            sentBytes += UInt64(data.ifi_obytes)
            receivedBytes += UInt64(data.ifi_ibytes)
        }

        return NetworkSample(sentBytes: sentBytes, receivedBytes: receivedBytes, timestamp: Date())
    }

    private func formatBytesPerSecond(_ bytesPerSecond: Double) -> String {
        if bytesPerSecond >= 1_048_576 {
            return String(format: "%.1fM/s", bytesPerSecond / 1_048_576)
        }
        return String(format: "%.0fK/s", bytesPerSecond / 1024)
    }
}

private struct NetworkSample {
    let sentBytes: UInt64
    let receivedBytes: UInt64
    let timestamp: Date
}
