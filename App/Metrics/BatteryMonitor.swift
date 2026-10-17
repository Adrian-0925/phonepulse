import UIKit

/// 电量和充电状态来自 UIDevice（公开 API）。
///
/// iOS 没有公开的充电电流/电压接口，充电功率是估算的（算法见 Core/BatteryPowerEstimator.swift），
/// 它代表电池的净充入功率，不等于充电头输出功率，界面上必须标注"估算"。
@MainActor
final class BatteryMonitor {
    private let device = UIDevice.current
    private var estimator = BatteryPowerEstimator()
    private var lastRawLevel: Float?

    /// 诊断用：系统给的原始电量值（-1 表示不可用）
    private(set) var rawLevel: Float = -1
    /// 诊断用：本次运行中观察到的最小电量跳变，用来判断系统是按 1% 还是 5% 报告电量
    private(set) var smallestObservedStep: Double?

    var changePointCount: Int { estimator.changePointCount }

    init() {
        device.isBatteryMonitoringEnabled = true
    }

    /// 用户在设置里填写的容量优先，否则用机型内置数据
    var capacityMAh: Int? {
        let override = UserDefaults.standard.integer(forKey: AppSettings.batteryCapacityKey)
        return override > 0 ? override : DeviceCatalog.current?.batteryMAh
    }

    func sample() -> BatterySample {
        rawLevel = device.batteryLevel
        trackStep(rawLevel)
        let level: Double? = rawLevel < 0 ? nil : Double(rawLevel)
        let state = BatteryState(device.batteryState)
        estimator.record(level: level, state: state, at: ProcessInfo.processInfo.systemUptime)
        return BatterySample(
            level: level,
            state: state,
            isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
            estimatedPowerWatts: estimator.estimatedWatts(capacityMAh: capacityMAh),
            capacityMAh: capacityMAh)
    }

    private func trackStep(_ level: Float) {
        guard level >= 0 else { return }
        defer { lastRawLevel = level }
        guard let lastRawLevel, level != lastRawLevel else { return }
        let step = Double(abs(level - lastRawLevel))
        smallestObservedStep = min(smallestObservedStep ?? step, step)
    }
}

private extension BatteryState {
    init(_ state: UIDevice.BatteryState) {
        switch state {
        case .unplugged: self = .unplugged
        case .charging: self = .charging
        case .full: self = .full
        default: self = .unknown
        }
    }
}
