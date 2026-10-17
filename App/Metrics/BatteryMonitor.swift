import UIKit

/// 电量和充电状态来自 UIDevice（公开 API）。
///
/// iOS 没有公开的充电电流/电压接口，所以充电功率是估算的：
///   功率(W) = 电量变化速度(%/h) × 电池容量(Ah) × 标称电压(3.85V)
/// 它代表电池的净充入功率，不等于充电头输出功率（中间有转换损耗和手机自身耗电），界面上必须标注"估算"。
/// 只用"电量发生变化的时间点"来计算，避免电量取整（1% 或 5% 一档）带来的误差，因此需要采样几分钟才有结果。
@MainActor
final class BatteryMonitor {
    private let device = UIDevice.current
    private let nominalVoltage = 3.85
    /// 只用最近 15 分钟内的变化点
    private let window: TimeInterval = 15 * 60
    /// 首末两个变化点至少相隔这么久才给出估算
    private let minimumSpan: TimeInterval = 60

    private var changePoints: [(time: TimeInterval, level: Double)] = []
    private var lastLevel: Double?
    private var lastState: BatteryState?

    init() {
        device.isBatteryMonitoringEnabled = true
    }

    /// 用户在设置里填写的容量优先，否则用机型内置数据
    var capacityMAh: Int? {
        let override = UserDefaults.standard.integer(forKey: AppSettings.batteryCapacityKey)
        return override > 0 ? override : DeviceCatalog.current?.batteryMAh
    }

    func sample() -> BatterySample {
        let level: Double? = device.batteryLevel < 0 ? nil : Double(device.batteryLevel)
        let state = BatteryState(device.batteryState)
        record(level: level, state: state)
        return BatterySample(
            level: level,
            state: state,
            isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
            estimatedPowerWatts: estimatedPowerWatts(state: state),
            capacityMAh: capacityMAh)
    }

    private func record(level: Double?, state: BatteryState) {
        let now = ProcessInfo.processInfo.systemUptime
        // 插拔充电器后旧数据作废
        if state != lastState {
            changePoints.removeAll()
            lastLevel = nil
            lastState = state
        }
        guard let level else { return }
        if let lastLevel, level != lastLevel {
            changePoints.append((now, level))
        }
        lastLevel = level
        changePoints.removeAll { now - $0.time > window }
    }

    private func estimatedPowerWatts(state: BatteryState) -> Double? {
        guard state == .charging || state == .unplugged,
              let capacity = capacityMAh,
              let first = changePoints.first,
              let last = changePoints.last,
              last.time - first.time >= minimumSpan else { return nil }
        let levelPerHour = (last.level - first.level) / (last.time - first.time) * 3600
        return levelPerHour * Double(capacity) / 1000 * nominalVoltage
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
