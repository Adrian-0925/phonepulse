import Foundation
import Network
import UIKit

/// 无状态的系统读数。App 和小组件扩展共用：小组件每次刷新时自己读取当下的数据，不依赖 App 是否打开过。
enum SystemProbe {
    private static let host = mach_host_self()

    static var thermal: ThermalLevel { ThermalLevel(ProcessInfo.processInfo.thermalState) }

    static func storage() -> StorageSample? {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        guard let values = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]),
              let total = values.volumeTotalCapacity,
              let available = values.volumeAvailableCapacityForImportantUsage else { return nil }
        return StorageSample(totalBytes: Int64(total), availableBytes: available)
    }

    /// 整机内存用 host_statistics64，本进程占用用 task_info 的 phys_footprint（与 Xcode 内存仪表一致）
    static func memory() -> MemorySample? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let pageSize = UInt64(vm_kernel_page_size)
        let usedPages = UInt64(stats.active_count) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)
        let total = ProcessInfo.processInfo.physicalMemory
        return MemorySample(
            totalBytes: total,
            usedBytes: min(usedPages * pageSize, total),
            appFootprintBytes: processFootprint())
    }

    /// 整机累计 CPU tick；系统不允许读取时返回 nil
    static func cpuTicks() -> CPUTicks? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        // 顺序为 CPU_STATE_USER, CPU_STATE_SYSTEM, CPU_STATE_IDLE, CPU_STATE_NICE
        let t = info.cpu_ticks
        return CPUTicks(user: t.0, system: t.1, idle: t.2, nice: t.3)
    }

    /// 所有网卡的原始累计计数（getifaddrs）
    static func interfaces() -> [InterfaceReading] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }

        var readings: [InterfaceReading] = []
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = pointer.pointee
            guard let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK),
                  let data = ifa.ifa_data else { continue }
            let stats = data.assumingMemoryBound(to: if_data.self).pointee
            readings.append(InterfaceReading(
                name: String(cString: ifa.ifa_name),
                receivedBytes: stats.ifi_ibytes,
                sentBytes: stats.ifi_obytes))
        }
        return readings
    }

    /// 当前网络连接类型：等系统第一次回报，最多等 timeout 秒
    static func connection(timeout: TimeInterval = 1) async -> ConnectionType {
        await withCheckedContinuation { continuation in
            let monitor = NWPathMonitor()
            let gate = ResumeGate()
            let queue = DispatchQueue(label: "PhonePulse.ConnectionProbe")
            monitor.pathUpdateHandler = { path in
                guard gate.claim() else { return }
                monitor.cancel()
                continuation.resume(returning: ConnectionType(path))
            }
            monitor.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) {
                guard gate.claim() else { return }
                monitor.cancel()
                continuation.resume(returning: ConnectionType.none)
            }
        }
    }

    private static func processFootprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.stride / MemoryLayout<natural_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : 0
    }
}

/// 电量相关读数来自 UIDevice，必须在主线程读取
@MainActor
enum BatteryProbe {
    struct Reading {
        /// 系统给的原始值，-1 表示不可用（模拟器）
        var rawLevel: Float
        var state: BatteryState
        var isLowPowerMode: Bool

        var level: Double? { rawLevel < 0 ? nil : Double(rawLevel) }
    }

    static func read() -> Reading {
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true
        return Reading(
            rawLevel: device.batteryLevel,
            state: BatteryState(device.batteryState),
            isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled)
    }
}

/// 用户手动填写的电池信息（来自系统设置，App 无法直接读取），保存在 App Group 里供小组件使用
struct BatterySettings {
    /// 自定义设计容量（未收录的机型用），0 表示用内置数据
    var designOverride: Int
    /// 最大容量百分比（设置 → 电池 → 电池健康），0 表示没填
    var healthPercent: Int
    /// 循环次数（iPhone 15 及以后：设置 → 通用 → 关于本机），0 表示没填
    var cycleCount: Int

    static var current: BatterySettings {
        let defaults = SharedStore.defaults
        return BatterySettings(
            designOverride: defaults.integer(forKey: SharedStore.Key.batteryCapacityOverride),
            healthPercent: defaults.integer(forKey: SharedStore.Key.batteryHealthPercent),
            cycleCount: defaults.integer(forKey: SharedStore.Key.batteryCycleCount))
    }

    var designMAh: Int? {
        designOverride > 0 ? designOverride : DeviceCatalog.current?.batteryMAh
    }

    var capacity: BatteryCapacity? {
        designMAh.map { BatteryCapacity(designMAh: $0, health: healthPercent > 0 ? Double(healthPercent) / 100 : nil) }
    }
}

extension BatteryState {
    init(_ state: UIDevice.BatteryState) {
        switch state {
        case .unplugged: self = .unplugged
        case .charging: self = .charging
        case .full: self = .full
        default: self = .unknown
        }
    }
}

extension ThermalLevel {
    init(_ state: ProcessInfo.ThermalState) {
        switch state {
        case .nominal: self = .nominal
        case .fair: self = .fair
        case .serious: self = .serious
        case .critical: self = .critical
        @unknown default: self = .nominal
        }
    }
}

extension ConnectionType {
    init(_ path: NWPath) {
        guard path.status == .satisfied else {
            self = .none
            return
        }
        if path.usesInterfaceType(.wifi) {
            self = .wifi
        } else if path.usesInterfaceType(.cellular) {
            self = .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            self = .wired
        } else {
            self = .other
        }
    }
}

/// 保证 continuation 只被 resume 一次（回调和超时都在同一个串行队列上执行）
private final class ResumeGate: @unchecked Sendable {
    private var claimed = false

    func claim() -> Bool {
        guard !claimed else { return false }
        claimed = true
        return true
    }
}
