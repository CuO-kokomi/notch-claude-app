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
    private var previousCPUTicks: [CPUTicks] = []

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    private func refresh() {
        cpuText = currentCPUUsage().map { String(format: "%.0f%%", $0) } ?? "--"
        memoryText = currentMemoryText()
        refreshNetworkText()
    }

    // host_processor_info 给的是开机以来的累计 tick，必须与上次采样做差值才是当前占用；
    // 直接用累计值算出来的是"开机至今平均值"，几乎不随负载变化。首次采样先显示占位。
    private func currentCPUUsage() -> Double? {
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

        guard result == KERN_SUCCESS, let cpuInfo else { return nil }
        defer {
            let byteCount = vm_size_t(cpuInfoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: cpuInfo), byteCount)
        }

        let cpuLoadInfoCount = Int(CPU_STATE_MAX)
        var samples: [CPUTicks] = []
        samples.reserveCapacity(Int(processorCount))
        for cpu in 0..<Int(processorCount) {
            let offset = cpu * cpuLoadInfoCount
            let user = Double(cpuInfo[offset + Int(CPU_STATE_USER)])
            let system = Double(cpuInfo[offset + Int(CPU_STATE_SYSTEM)])
            let nice = Double(cpuInfo[offset + Int(CPU_STATE_NICE)])
            let idle = Double(cpuInfo[offset + Int(CPU_STATE_IDLE)])
            samples.append(CPUTicks(used: user + system + nice, total: user + system + nice + idle))
        }

        let previous = previousCPUTicks
        previousCPUTicks = samples
        // 首次采样，或核心数变化（E/P 核上下线）导致无法逐核对齐时，等下一轮。
        guard previous.count == samples.count, !samples.isEmpty else { return nil }

        var usageSum = 0.0
        var counted = 0
        for (index, sample) in samples.enumerated() {
            let totalDelta = sample.total - previous[index].total
            let usedDelta = sample.used - previous[index].used
            guard totalDelta > 0 else { continue }  // 该核这段时间没跑（已下线）
            usageSum += min(100, max(0, usedDelta / totalDelta * 100))
            counted += 1
        }
        guard counted > 0 else { return nil }
        return usageSum / Double(counted)
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
        // 对齐活动监视器的「已用内存」= App 内存 + 联动内存 + 已压缩。
        // App 内存是匿名页（internal - purgeable）；用 active 会把活跃的文件缓存算进来，
        // 又漏掉 inactive 的匿名页，两头都不准。
        let app = (Double(stats.internal_page_count) - Double(stats.purgeable_count)) * pageSize
        let wired = Double(stats.wire_count) * pageSize
        let compressed = Double(stats.compressor_page_count) * pageSize
        let usedGB = max(0, app + wired + compressed) / 1_073_741_824
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

        // 逐接口做差再求和：接口计数器各自独立回绕/重置，合并后就无法分辨了。
        var sentDelta: UInt64 = 0
        var receivedDelta: UInt64 = 0
        for (name, current) in sample.perInterface {
            guard let previous = previousSample.perInterface[name] else { continue }  // 新接口，下轮再算
            sentDelta += Self.counterDelta(from: previous.sent, to: current.sent, interval: interval)
            receivedDelta += Self.counterDelta(from: previous.received, to: current.received, interval: interval)
        }
        uploadText = formatBytesPerSecond(Double(sentDelta) / interval)
        downloadText = formatBytesPerSecond(Double(receivedDelta) / interval)
        previousNetworkSample = sample
    }

    // ifi_ibytes/ifi_obytes 是 32 位计数器，每 4GB 回绕一次；直接相减会得到负数
    // （旧实现钳成 0，高速下载时每过 4GB 就闪一次 0K/s）。回绕按补 2^32 修正。
    // 计数器归零（接口重连）也会走到这里，但断开时接口会失去 IFF_UP 而退出采样，
    // 回来时没有上一轮数据自然跳过；这里的带宽上限只兜底两次采样之间快速重连的情况。
    private static func counterDelta(from previous: UInt32, to current: UInt32, interval: TimeInterval) -> UInt64 {
        if current >= previous { return UInt64(current - previous) }
        let wrapped = UInt64(UInt32.max) - UInt64(previous) + UInt64(current) + 1
        let maxPlausibleBytes = 1_250_000_000.0 * interval  // 10 Gbps
        return Double(wrapped) <= maxPlausibleBytes ? wrapped : 0
    }

    private func currentNetworkSample() -> NetworkSample? {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let firstAddress = addresses else { return nil }
        defer { freeifaddrs(addresses) }

        var perInterface: [String: InterfaceCounters] = [:]
        var pointer: UnsafeMutablePointer<ifaddrs>? = firstAddress

        while let interface = pointer?.pointee {
            defer { pointer = interface.ifa_next }
            guard interface.ifa_addr.pointee.sa_family == UInt8(AF_LINK),
                  (interface.ifa_flags & UInt32(IFF_UP)) != 0,
                  (interface.ifa_flags & UInt32(IFF_LOOPBACK)) == 0,
                  let data = interface.ifa_data?.assumingMemoryBound(to: if_data.self).pointee,
                  // 只统计物理网卡：VPN / 代理 TUN（utun*，IFT_OTHER）承载的流量同时也会
                  // 走物理网卡，两者相加会让速度翻倍。物理网卡已覆盖全部出网流量。
                  data.ifi_type == UInt8(IFT_ETHER) else {
                continue
            }
            perInterface[String(cString: interface.ifa_name)] =
                InterfaceCounters(sent: data.ifi_obytes, received: data.ifi_ibytes)
        }

        guard !perInterface.isEmpty else { return nil }
        return NetworkSample(perInterface: perInterface, timestamp: Date())
    }

    private func formatBytesPerSecond(_ bytesPerSecond: Double) -> String {
        if bytesPerSecond >= 1_048_576 {
            return String(format: "%.1fM/s", bytesPerSecond / 1_048_576)
        }
        return String(format: "%.0fK/s", bytesPerSecond / 1024)
    }
}

// 单个核心的累计 tick 快照：used = user+system+nice，total 含 idle。
private struct CPUTicks {
    let used: Double
    let total: Double
}

private struct InterfaceCounters {
    let sent: UInt32
    let received: UInt32
}

private struct NetworkSample {
    let perInterface: [String: InterfaceCounters]
    let timestamp: Date
}
