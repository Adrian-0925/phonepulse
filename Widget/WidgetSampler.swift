import Foundation

/// 小组件每次刷新时自己读取当下的数据，不依赖 App 是否打开过。
/// 读数用 InstantSampler（和灵动岛「刷新」按钮同一套）：网速是"刷新那一秒"的速度，不是持续监测。
enum WidgetSampler {
    private static let historyKey = "widgetBatteryHistory"

    static func sample() async -> (snapshot: MetricsSnapshot, history: [BatteryPoint]) {
        let instant = await InstantSampler.read()
        let reading = instant.battery
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
        let snapshot = MetricsSnapshot(
            timestamp: .now,
            network: instant.network,
            cpu: instant.cpu,
            memory: instant.memory,
            battery: battery,
            storage: instant.storage,
            thermal: instant.thermal)
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
