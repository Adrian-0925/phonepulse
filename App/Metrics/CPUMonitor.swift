import Foundation

/// CPU 占用：优先读整机 CPU tick（host_statistics），读不到时退回到只统计本 App 进程（getrusage）。
/// 两次采样之间的差值才是占用率，所以第一次调用返回 nil。tick 差值计算在 Core/CPULoad.swift。
final class CPUMonitor {
    private let host = mach_host_self()
    private let coreCount = ProcessInfo.processInfo.activeProcessorCount
    private var lastTicks: CPUTicks?
    private var lastProcess: (user: TimeInterval, system: TimeInterval, uptime: TimeInterval)?

    func sample() -> CPUSample? {
        guard let ticks = readHostTicks() else { return sampleProcess() }
        defer { lastTicks = ticks }
        guard let previous = lastTicks, let load = CPULoad(from: previous, to: ticks) else { return nil }
        return CPUSample(
            usage: load.usage,
            user: load.user,
            system: load.system,
            isSystemWide: true,
            coreCount: coreCount)
    }

    func pause() {
        lastTicks = nil
        lastProcess = nil
    }

    private func readHostTicks() -> CPUTicks? {
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

    private func sampleProcess() -> CPUSample? {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { return nil }
        let user = TimeInterval(usage.ru_utime.tv_sec) + TimeInterval(usage.ru_utime.tv_usec) / 1_000_000
        let system = TimeInterval(usage.ru_stime.tv_sec) + TimeInterval(usage.ru_stime.tv_usec) / 1_000_000
        let now = ProcessInfo.processInfo.systemUptime
        defer { lastProcess = (user, system, now) }
        guard let previous = lastProcess, now > previous.uptime else { return nil }

        // 按全部核心的总算力归一化
        let capacity = (now - previous.uptime) * Double(coreCount)
        let userFraction = (user - previous.user) / capacity
        let systemFraction = (system - previous.system) / capacity
        return CPUSample(
            usage: min(userFraction + systemFraction, 1),
            user: userFraction,
            system: systemFraction,
            isSystemWide: false,
            coreCount: coreCount)
    }
}
