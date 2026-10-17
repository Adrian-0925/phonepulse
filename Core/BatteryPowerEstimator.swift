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

    /// 正数为充入、负数为放电；数据不足、已充满或不知道容量时返回 nil
    func estimatedWatts(capacityMAh: Int?) -> Double? {
        guard lastState == .charging || lastState == .unplugged,
              let capacityMAh, capacityMAh > 0,
              let first = changePoints.first,
              let last = changePoints.last,
              last.time - first.time >= minimumSpan else { return nil }
        let levelPerHour = (last.level - first.level) / (last.time - first.time) * 3600
        return levelPerHour * Double(capacityMAh) / 1000 * Self.nominalVoltage
    }
}
