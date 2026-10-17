import Foundation

/// 小组件每次刷新时自己读取当下的数据，不依赖 App 是否打开过。
/// 网速和 CPU 都需要两次读数，所以中间等 1 秒：小组件上的网速是"刷新那一秒"的速度，不是持续监测。
enum WidgetSampler {
    private static let historyKey = "widgetBatteryHistory"

    static func sample() async -> (snapshot: MetricsSnapshot, history: [BatteryPoint]) {
        let firstTicks = SystemProbe.cpuTicks()
        let firstInterfaces = SystemProbe.interfaces()
        let start = Date.now
        async let connection = SystemProbe.connection(timeout: 1)
        try? await Task.sleep(for: .seconds(1))
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

        let reading = await BatteryProbe.read()
        let history = recordHistory(reading)
        // 小组件刷新间隔较长，用历史曲线推算速度；App 打开时会有更精确的数据
        let levelPerHour = history.recentLevelPerHour()
        let fullCharge = BatterySettings.current.capacity?.fullChargeMAh
        var watts: Double?
        if let levelPerHour, let fullCharge {
            watts = BatteryPowerEstimator.watts(levelPerHour: levelPerHour, capacityMAh: fullCharge)
        }

        let battery = BatterySample(
            level: reading.level,
            state: reading.state,
            isLowPowerMode: reading.isLowPowerMode,
            estimatedPowerWatts: watts,
            capacityMAh: fullCharge,
            levelPerHour: levelPerHour)
        let network = NetworkSample(
            downloadBytesPerSecond: Double(delta.received) / elapsed,
            uploadBytesPerSecond: Double(delta.sent) / elapsed,
            sessionWifiBytes: 0,
            sessionCellularBytes: 0,
            connection: await connection)
        let snapshot = MetricsSnapshot(
            timestamp: .now,
            network: network,
            cpu: cpu,
            memory: SystemProbe.memory(),
            battery: battery,
            storage: SystemProbe.storage(),
            thermal: SystemProbe.thermal)
        return (snapshot, history.points)
    }

    /// 电量历史存在小组件自己的存储里（免费账号没有 App Group 也能用）
    private static func recordHistory(_ reading: BatteryProbe.Reading) -> BatteryHistory {
        let defaults = UserDefaults.standard
        var history = defaults.data(forKey: historyKey)
            .flatMap { try? JSONDecoder().decode(BatteryHistory.self, from: $0) } ?? BatteryHistory()
        if let level = reading.level {
            history.append(BatteryPoint(time: .now, level: level, isCharging: reading.state.isPluggedIn))
            if let data = try? JSONEncoder().encode(history) {
                defaults.set(data, forKey: historyKey)
            }
        }
        return history
    }
}
