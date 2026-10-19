import Foundation

/// 现场读取一次的所有指标
struct InstantReading {
    var cpu: CPUSample?
    var network: NetworkSample
    var battery: BatteryProbe.Reading
    var memory: MemorySample?
    var storage: StorageSample?
    var thermal: ThermalLevel
}

/// App 没在每秒采样时，现场读一次数据：小组件每次刷新、灵动岛「刷新」按钮（App 被系统暂停时）都用它。
/// 读数方法和 App 每秒采样完全一样（SystemProbe），只是网速和 CPU 需要两次读数，中间等 window 秒。
enum InstantSampler {
    static func read(window: TimeInterval = 1) async -> InstantReading {
        let firstTicks = SystemProbe.cpuTicks()
        let firstInterfaces = SystemProbe.interfaces()
        let start = Date.now
        async let connection = SystemProbe.connection(timeout: window)
        try? await Task.sleep(for: .seconds(window))
        let elapsed = max(Date.now.timeIntervalSince(start), 0.1)
        let secondTicks = SystemProbe.cpuTicks()
        let secondInterfaces = SystemProbe.interfaces()

        var counter = TrafficCounter()
        _ = counter.update(with: firstInterfaces)
        let delta = counter.update(with: secondInterfaces)

        var cpu: CPUSample?
        if let firstTicks, let secondTicks, let load = CPULoad(from: firstTicks, to: secondTicks) {
            cpu = CPUSample(
                usage: load.usage,
                user: load.user,
                system: load.system,
                isSystemWide: true,
                coreCount: ProcessInfo.processInfo.activeProcessorCount)
        }

        let battery = await BatteryProbe.read()
        let network = NetworkSample(
            downloadBytesPerSecond: Double(delta.received) / elapsed,
            uploadBytesPerSecond: Double(delta.sent) / elapsed,
            sessionWifiBytes: 0,
            sessionCellularBytes: 0,
            connection: await connection)
        return InstantReading(
            cpu: cpu,
            network: network,
            battery: battery,
            memory: SystemProbe.memory(),
            storage: SystemProbe.storage(),
            thermal: SystemProbe.thermal)
    }
}
