import Foundation

/// 电量和充电状态来自 UIDevice（公开 API），读取在 Platform/SystemProbes.swift。
///
/// iOS 没有公开的充电电流/电压接口，充电功率是估算的（算法见 Core/BatteryPowerEstimator.swift），
/// 它代表电池的净充入功率，不等于充电头输出功率，界面上必须标注"估算"。
@MainActor
final class BatteryMonitor {
    private var estimator = BatteryPowerEstimator()
    private var lastRawLevel: Float?

    /// 诊断用：系统给的原始电量值（-1 表示不可用）
    private(set) var rawLevel: Float = -1
    /// 诊断用：本次运行中观察到的最小电量跳变，用来判断系统是按 1% 还是 5% 报告电量
    private(set) var smallestObservedStep: Double?

    var changePointCount: Int { estimator.changePointCount }
    /// 诊断用：最近几次电量变化的间隔（秒）
    var recentChangeIntervals: [TimeInterval] { estimator.recentIntervals }

    func sample(at date: Date) -> BatterySample {
        let reading = BatteryProbe.read()
        rawLevel = reading.rawLevel
        trackStep(rawLevel)
        estimator.record(level: reading.level, state: reading.state, at: date.timeIntervalSinceReferenceDate)
        // 用"当前满电容量"（设计容量 × 用户填写的最大容量百分比）估算功率，更贴近老化后的电池
        let fullCharge = BatterySettings.current.capacity?.fullChargeMAh
        return BatterySample(
            level: reading.level,
            state: reading.state,
            isLowPowerMode: reading.isLowPowerMode,
            estimatedPowerWatts: estimator.estimatedWatts(capacityMAh: fullCharge),
            capacityMAh: fullCharge,
            levelPerHour: estimator.levelPerHour(),
            power: estimator.status())
    }

    /// App 停止采样时调用。回来后第一个读数只当起点；暂停太久则重新开始一轮测定
    func pause(at date: Date) {
        estimator.pause(at: date.timeIntervalSinceReferenceDate)
    }

    private func trackStep(_ level: Float) {
        guard level >= 0 else { return }
        defer { lastRawLevel = level }
        guard let lastRawLevel, level != lastRawLevel else { return }
        let step = Double(abs(level - lastRawLevel))
        smallestObservedStep = min(smallestObservedStep ?? step, step)
    }
}
