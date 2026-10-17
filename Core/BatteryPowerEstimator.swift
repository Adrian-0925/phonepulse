import Foundation

/// 充电功率估算：功率(W) = 电量变化速度(每小时) × 电池容量(Ah) × 标称电压(3.85V)。
///
/// 只用"电量发生变化的时间点"来计算，避免电量取整（1% 或 5% 一档）带来的误差，所以需要采样几分钟才有结果。
/// 结果是电池的净充入功率，不等于充电头输出功率。纯计算，时间由调用方传入，方便单元测试。
struct BatteryPowerEstimator {
    static let nominalVoltage = 3.85

    /// 只用最近这段时间内的变化点
    var window: TimeInterval = 15 * 60
    /// 首末两个变化点至少相隔这么久才给出估算
    var minimumSpan: TimeInterval = 60

    private var changePoints: [(time: TimeInterval, level: Double)] = []
    private var lastLevel: Double?
    private var lastState: BatteryState?

    var changePointCount: Int { changePoints.count }

    mutating func record(level: Double?, state: BatteryState, at time: TimeInterval) {
        // 插拔充电器后旧数据作废
        if state != lastState {
            changePoints.removeAll()
            lastLevel = nil
            lastState = state
        }
        guard let level else { return }
        if let lastLevel, level != lastLevel {
            changePoints.append((time, level))
        }
        lastLevel = level
        changePoints.removeAll { time - $0.time > window }
    }

    /// 电量变化速度（每小时变化的比例），正数为充电、负数为耗电；数据不足或已充满时返回 nil
    func levelPerHour() -> Double? {
        guard lastState == .charging || lastState == .unplugged,
              let first = changePoints.first,
              let last = changePoints.last,
              last.time - first.time >= minimumSpan else { return nil }
        return (last.level - first.level) / (last.time - first.time) * 3600
    }

    /// 正数为充入、负数为放电；数据不足、已充满或不知道容量时返回 nil
    func estimatedWatts(capacityMAh: Int?) -> Double? {
        guard let capacityMAh, capacityMAh > 0, let rate = levelPerHour() else { return nil }
        return Self.watts(levelPerHour: rate, capacityMAh: capacityMAh)
    }

    static func watts(levelPerHour: Double, capacityMAh: Int) -> Double {
        levelPerHour * Double(capacityMAh) / 1000 * nominalVoltage
    }
}

enum ChargeForecast {
    /// 按当前速度充到 100% 还需要多久；已充满或速度太慢（每小时不到 1%）时返回 nil。
    /// 注意：iOS 的优化充电会在 80% 左右暂停，实际可能更久。
    static func timeToFull(level: Double, levelPerHour: Double) -> TimeInterval? {
        guard levelPerHour >= 0.01, level < 1 else { return nil }
        return (1 - level) / levelPerHour * 3600
    }
}
