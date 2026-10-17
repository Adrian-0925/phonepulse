import Foundation

/// CPU 占用：优先读整机 CPU tick（host_statistics），读不到时退回到只统计本 App 进程（getrusage）。
/// 两次采样之间的差值才是占用率，所以第一次调用返回 nil。tick 差值计算在 Core/CPULoad.swift。
final class CPUMonitor {
    private let coreCount = ProcessInfo.processInfo.activeProcessorCount
    private var lastTicks: CPUTicks?
    private var lastProcess: (user: TimeInterval, system: TimeInterval, uptime: TimeInterval)?

    func sample() -> CPUSample? {
        guard let ticks = SystemProbe.cpuTicks() else { return sampleProcess() }
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
