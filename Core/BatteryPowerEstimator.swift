import Foundation

/// 功率测定进行到哪一步。App、充电大屏、灵动岛都按它区分显示，说法保持一致
enum PowerPhase: String, Codable, Equatable {
    /// 正在采集：电量变化次数还不够，没有结果
    case collecting
    /// 初步估算：只观察到很短一段，之后还会变
    case preliminary
    /// 较稳定：观察了多次电量变化、跨度够长
    case stable
    /// 电量很久没变（比如充到 80% 后的优化充电），之前的速度已不适用，只能给出上限
    case slowed
}

/// 一轮功率测定的状态。插拔充电器、App 暂停太久后回来，都会开始新的一轮，不沿用上一轮的结果
struct PowerStatus: Codable, Equatable {
    var phase: PowerPhase
    /// 本轮开始的时间
    var roundStart: Date
    /// 本轮最近一次电量变化的时间；有结果时就是结果的更新时间
    var lastChangeAt: Date?
    /// 本轮观察到的电量变化次数
    var changes: Int
    /// 只考虑采样时刻误差时，速度的相对误差（0.05 = ±5%）；没有结果时为 nil
    var timingError: Double?
    /// slowed 时：最近一段速度的上限（每小时比例，正数）
    var slowedBoundPerHour: Double?
}

/// 充电功率估算：功率(W) = 电量变化速度(每小时) × 电池容量(Ah) × 标称电压(3.85V)。
///
/// iOS 不开放电流电压，只能看电量。电量是取整的（1% 或 5% 一档），所以只用"电量刚变化的那一刻"计算：
/// 两次变化之间正好涨了一档，时间误差只有采样间隔（App 每秒采一次）。因此至少要看到两次电量变化才有结果，
/// 这是无法再缩短的部分：1% 一档、20W 快充时约 1 分钟，5% 一档或慢充时要几分钟。
///
/// 结果是电池的净充入功率，不等于充电头输出功率。纯计算，时间由调用方传入（秒，timeIntervalSinceReferenceDate），方便单元测试。
struct BatteryPowerEstimator {
    static let nominalVoltage = 3.85
    /// 电量差别小于这个值不算变化
    static let minimumChange = 0.001

    /// 只用最近这段时间内的变化点
    var window: TimeInterval = 15 * 60
    /// 初步估算：首末两个变化点至少相隔这么久（每秒采样时，计时误差约 ±2 秒 ÷ 36 秒 ≈ ±5%）
    var minimumSpan: TimeInterval = 36
    /// 较稳定：至少这么多个变化点（两段间隔），且跨度至少这么久
    var stableChanges = 3
    var stableSpan: TimeInterval = 150
    /// 变化点很多（快充）时只用最近这么长的一段，速度变了能更快跟上
    var responsiveSpan: TimeInterval = 180
    /// App 暂停超过这么久才回来，中间可能拔插过，重新开始一轮
    var resumeLimit: TimeInterval = 150
    /// 电量多久没变算"放缓"：超过平均间隔的这么多倍，且至少 slowedMinimum 秒
    var slowedFactor = 2.5
    var slowedMinimum: TimeInterval = 90

    private struct ChangePoint: Equatable {
        var time: TimeInterval
        var level: Double
        /// 和上一次读数相隔多久：电量是在这段时间里的某一刻变的，就是这个点的计时误差
        var gap: TimeInterval
    }

    private var changePoints: [ChangePoint] = []
    private var lastLevel: Double?
    private var lastState: BatteryState?
    private var lastTime: TimeInterval?
    private var roundStart: TimeInterval?
    private var pausedAt: TimeInterval?
    /// 本轮观察到的变化次数（不随窗口裁剪减少）
    private var roundChanges = 0
    /// 本轮最近一次变化（窗口裁剪后也保留，用来判断放缓）
    private var lastChange: ChangePoint?
    /// 最近一次电量跳变的幅度（1% 或 5%）
    private var lastStep: Double?
    /// 从这一刻起电量没再变过（最近一次变化，或暂停回来时发现电量已变）
    private var quietSince: TimeInterval?
    /// 诊断用：最近几次电量变化的间隔（秒），用来看系统多久更新一次电量
    private(set) var recentIntervals: [TimeInterval] = []

    var changePointCount: Int { changePoints.count }

    mutating func record(level: Double?, state: BatteryState, at time: TimeInterval) {
        if state != lastState {
            // 插拔充电器后旧数据作废
            startRound(at: time)
            lastState = state
        } else if let pausedAt {
            self.pausedAt = nil
            let previousLevel = lastLevel
            lastLevel = nil
            if time - pausedAt > resumeLimit || Self.reversed(from: previousLevel, to: level, state: state) {
                startRound(at: time)
            } else if let level, let previousLevel, abs(level - previousLevel) >= Self.minimumChange {
                // 暂停期间电量变过，但不知道是哪一刻：回来后的第一个读数只当起点，"多久没变"从现在算起
                quietSince = time
            }
            // 暂停前的变化点是看到的真实变化时刻，仍然有效
        }
        let gap = lastTime.map { time - $0 } ?? 0
        lastTime = time
        guard let level else { return }
        // 系统电量至少 1% 一档；小于 0.1% 的差别只是浮点误差，不算变化
        if let lastLevel, abs(level - lastLevel) >= Self.minimumChange {
            let point = ChangePoint(time: time, level: level, gap: gap)
            if let lastChange {
                recentIntervals.append(time - lastChange.time)
                if recentIntervals.count > 8 {
                    recentIntervals.removeFirst(recentIntervals.count - 8)
                }
            }
            lastStep = abs(level - lastLevel)
            changePoints.append(point)
            lastChange = point
            quietSince = time
            roundChanges += 1
        }
        lastLevel = level
        changePoints.removeAll { time - $0.time > window }
    }

    /// App 停止采样时调用（进入后台被暂停前）
    mutating func pause(at time: TimeInterval) {
        guard pausedAt == nil, lastState != nil else { return }
        pausedAt = time
    }

    /// 电量变化速度（每小时变化的比例），正数为充电、负数为耗电；数据不足、已放缓或已充满时返回 nil
    func levelPerHour() -> Double? {
        guard isMeasuring, !isSlowed, let fit = fit() else { return nil }
        return (fit.last.level - fit.first.level) / (fit.last.time - fit.first.time) * 3600
    }

    /// 正数为充入、负数为放电；数据不足、已充满或不知道容量时返回 nil
    func estimatedWatts(capacityMAh: Int?) -> Double? {
        guard let capacityMAh, capacityMAh > 0, let rate = levelPerHour() else { return nil }
        return Self.watts(levelPerHour: rate, capacityMAh: capacityMAh)
    }

    /// 当前这一轮测定到哪一步；没在充电也没在耗电（已充满、状态未知）或读不到电量时返回 nil
    func status() -> PowerStatus? {
        guard isMeasuring, lastLevel != nil, let roundStart else { return nil }
        var status = PowerStatus(
            phase: .collecting,
            roundStart: Self.date(roundStart),
            lastChangeAt: lastChange.map { Self.date($0.time) },
            changes: roundChanges)
        if isSlowed, let quietSince, let lastStep, let now = lastTime {
            status.phase = .slowed
            status.slowedBoundPerHour = lastStep / max(now - quietSince, 1) * 3600
        } else if let fit = fit() {
            let span = fit.last.time - fit.first.time
            status.phase = fit.count >= stableChanges && span >= stableSpan ? .stable : .preliminary
            status.timingError = (fit.first.gap + fit.last.gap) / span
        }
        return status
    }

    static func watts(levelPerHour: Double, capacityMAh: Int) -> Double {
        levelPerHour * Double(capacityMAh) / 1000 * nominalVoltage
    }

    // MARK: - 内部

    private var isMeasuring: Bool {
        lastState == .charging || lastState == .unplugged
    }

    private mutating func startRound(at time: TimeInterval) {
        changePoints.removeAll()
        lastLevel = nil
        roundStart = time
        roundChanges = 0
        lastChange = nil
        lastStep = nil
        quietSince = nil
        recentIntervals.removeAll()
        pausedAt = nil
    }

    /// 计算用的首末两个变化点。变化点足够多时只用最近 responsiveSpan 内的一段
    private func fit() -> (first: ChangePoint, last: ChangePoint, count: Int)? {
        guard changePoints.count >= 2, let last = changePoints.last else { return nil }
        var start = 0
        if let index = changePoints.lastIndex(where: { last.time - $0.time >= responsiveSpan }),
           changePoints.count - index >= 4 {
            start = index
        }
        let first = changePoints[start]
        guard last.time - first.time >= minimumSpan else { return nil }
        return (first, last, changePoints.count - start)
    }

    /// 平均多久变一次电量
    private var typicalInterval: TimeInterval? {
        if let fit = fit() {
            return (fit.last.time - fit.first.time) / Double(fit.count - 1)
        }
        guard !recentIntervals.isEmpty else { return nil }
        return recentIntervals.reduce(0, +) / Double(recentIntervals.count)
    }

    /// 电量已经比平时久得多没变了：之前算出的速度不再适用
    private var isSlowed: Bool {
        guard roundChanges >= 2, let quietSince, let now = lastTime, let typical = typicalInterval else { return false }
        return now - quietSince > max(typical * slowedFactor, slowedMinimum)
    }

    /// 暂停回来后电量往反方向走了（充电时变少、耗电时变多），说明中间拔插过
    private static func reversed(from previous: Double?, to level: Double?, state: BatteryState) -> Bool {
        guard let previous, let level else { return false }
        switch state {
        case .charging: return level < previous
        case .unplugged: return level > previous
        default: return false
        }
    }

    private static func date(_ time: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: time)
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
