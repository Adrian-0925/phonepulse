import Foundation

/// 一天里的时段，用来总结「常在什么时候充电」
enum DayPeriod: String, Equatable, Hashable {
    case lateNight, morning, forenoon, noon, afternoon, evening

    init(hour: Int) {
        switch hour {
        case 0..<5: self = .lateNight
        case 5..<9: self = .morning
        case 9..<12: self = .forenoon
        case 12..<14: self = .noon
        case 14..<18: self = .afternoon
        default: self = .evening
        }
    }

    var label: String {
        switch self {
        case .lateNight: "深夜"
        case .morning: "早上"
        case .forenoon: "上午"
        case .noon: "中午"
        case .afternoon: "下午"
        case .evening: "晚上"
        }
    }

    /// 夜里插上、一放好几个小时：系统的优化充电主要就是为这种情况设计的
    var isNight: Bool { self == .evening || self == .lateNight }
}

/// 某次充电和「平时」比：在这次和以往记录都完整覆盖的同一段电量区间里比较速度
struct SpeedVersusUsual: Equatable {
    enum Verdict: Equatable {
        /// 以往的记录不够，或者和这次没有重合的电量区间
        case insufficient
        /// 差别在估算误差和日常波动范围内
        case similar(difference: Double)
        /// 比平时快（0.2 = 快 20%）
        case faster(by: Double)
        /// 比平时慢（0.2 = 速度低 20%）
        case slower(by: Double)
    }

    /// 比较用的电量区间（百分比）；没有重合区间时为 nil
    var range: ClosedRange<Int>?
    /// 这次走完这个区间用了多久
    var duration: TimeInterval?
    /// 以往记录走完同一区间用时的中位数
    var usualDuration: TimeInterval?
    /// 有多少条以往记录覆盖了这个区间
    var baselineCount: Int
    var verdict: Verdict
}

/// 充电习惯（至少 ChargeInsights.habitMinimum 条记录才总结）
struct ChargeHabits: Equatable {
    var sessionCount: Int
    /// 常见起止电量和单次用时（中位数）
    var typicalStartLevel: Double?
    var typicalEndLevel: Double?
    var typicalDuration: TimeInterval?
    /// 超过一半的充电在这个时段开始；没有明显规律时为 nil
    var commonStartPeriod: DayPeriod?
    /// 在 commonStartPeriod 开始的次数
    var commonStartCount: Int
    /// 看到了插电那一刻的记录数（只有这些的开始时间是准的）
    var observedStartCount: Int
}

/// 最近几天的充电汇总
struct RecentCharging: Equatable {
    var days: Int
    var count: Int
    /// App 记录到的充入电量合计（比例，1.1 = 110%，约 1.1 次满电）
    var totalGained: Double
    /// 充电时温控偏高及以上的次数
    var heatCount: Int
    /// 疑似进入优化充电的次数
    var optimizedCount: Int
    /// 充到 100% 的次数
    var reachedFullCount: Int
}

/// 把充电记录整理成「结论」：这次比平时快还是慢、你通常怎么充、最近充了多少。
/// iOS 能读到的电池数据就这么几项，再加数字意义不大，差别在于把数字解读成用户看得懂的判断。
/// 纯计算，时间和日历由调用方传入，方便单元测试。
enum ChargeInsights {
    /// 至少要有这么多条以往记录覆盖同一电量区间，才和「平时」比
    static let baselineRuns = 2
    /// 和「平时」比时最多看最近这么多条记录（太早的记录可能是旧充电器、旧电池）
    static let baselineLimit = 30
    /// 至少这么多条记录才总结充电习惯
    static let habitMinimum = 3
    /// 「最近」统计的天数
    static let recentDays = 7

    // MARK: - 和平时比

    /// history 是已结束的记录（最新的在前），里面有 session 本身也没关系，会被排除
    static func speedVersusUsual(_ session: ChargeSession, history: [ChargeSession]) -> SpeedVersusUsual {
        let others: [ChargeSession] = Array(history.filter { $0.id != session.id }.prefix(baselineLimit))
        let target = AccessoryComparison.entries(of: session)
        let otherEntries: [[Int: (time: Date, segment: Int)]] = others.map { AccessoryComparison.entries(of: $0) }
        guard let range = baselineRange(target, otherEntries),
              let run = AccessoryComparison.run(session, entries: target, range: range) else {
            return SpeedVersusUsual(range: nil, duration: nil, usualDuration: nil, baselineCount: 0, verdict: .insufficient)
        }

        var baseline: [RangeRun] = []
        for (other, entries) in zip(others, otherEntries) {
            if let otherRun = AccessoryComparison.run(other, entries: entries, range: range) {
                baseline.append(otherRun)
            }
        }
        let usualRate = AccessoryComparison.median(baseline.map(\.levelPerHour))
        let usualDuration = AccessoryComparison.median(baseline.map(\.duration))

        var verdict = SpeedVersusUsual.Verdict.insufficient
        if baseline.count >= baselineRuns, let usualRate, usualRate > 0, run.levelPerHour > 0 {
            let ratio = run.levelPerHour / usualRate - 1
            if abs(ratio) < AccessoryComparison.similarThreshold {
                verdict = .similar(difference: abs(ratio))
            } else if ratio > 0 {
                verdict = .faster(by: ratio)
            } else {
                verdict = .slower(by: -ratio)
            }
        }
        return SpeedVersusUsual(range: range, duration: run.duration, usualDuration: usualDuration,
                                baselineCount: baseline.count, verdict: verdict)
    }

    /// 这次充电完整覆盖、以往记录也尽量多覆盖的电量区间：
    /// 先看覆盖的记录数（最多算到 baselineRuns），再优先 80% 以下，再看宽度
    static func baselineRange(_ target: [Int: (time: Date, segment: Int)], _ others: [[Int: (time: Date, segment: Int)]]) -> ClosedRange<Int>? {
        guard !target.isEmpty, !others.isEmpty else { return nil }
        let width = AccessoryComparison.minimumWidth
        var best: ClosedRange<Int>?
        var bestScore: [Int] = []
        for low in 1...(100 - width) {
            for high in (low + width)...100 {
                guard AccessoryComparison.covers(target, low: low, high: high) else { continue }
                let count = others.filter { AccessoryComparison.covers($0, low: low, high: high) }.count
                guard count > 0 else { continue }
                let score: [Int] = [min(count, baselineRuns), high <= AccessoryComparison.preferredCeiling ? 1 : 0, high - low, count]
                // 分数更高才替换；分数相同保留先找到的（电量更低的区间）
                if best == nil || bestScore.lexicographicallyPrecedes(score) {
                    best = low...high
                    bestScore = score
                }
            }
        }
        return best
    }

    // MARK: - 充电习惯

    static func habits(_ sessions: [ChargeSession], calendar: Calendar) -> ChargeHabits? {
        guard sessions.count >= habitMinimum else { return nil }
        let starts: [Double] = sessions.compactMap { $0.samples.first?.level }
        let ends: [Double] = sessions.compactMap { $0.samples.last?.level }
        let durations: [TimeInterval] = sessions.compactMap { session -> TimeInterval? in
            guard let end = session.endDate else { return nil }
            return end.timeIntervalSince(session.startDate)
        }

        // 没看到插电那一刻的记录，开始时间只是「App 打开的时间」，不算时段
        let observed = sessions.filter { $0.startObserved }
        var periodCounts: [DayPeriod: Int] = [:]
        for session in observed {
            periodCounts[DayPeriod(hour: calendar.component(.hour, from: session.startDate)), default: 0] += 1
        }
        var commonPeriod: DayPeriod?
        var commonCount = 0
        if observed.count >= habitMinimum, let top = periodCounts.max(by: { $0.value < $1.value }), top.value * 2 > observed.count {
            commonPeriod = top.key
            commonCount = top.value
        }

        return ChargeHabits(
            sessionCount: sessions.count,
            typicalStartLevel: AccessoryComparison.median(starts),
            typicalEndLevel: AccessoryComparison.median(ends),
            typicalDuration: AccessoryComparison.median(durations),
            commonStartPeriod: commonPeriod,
            commonStartCount: commonCount,
            observedStartCount: observed.count)
    }

    // MARK: - 最近

    static func recent(_ sessions: [ChargeSession], now: Date, days: Int = recentDays) -> RecentCharging {
        let since = now.addingTimeInterval(-Double(days) * 86_400)
        var count = 0
        var gained: Double = 0
        var heat = 0
        var optimized = 0
        var reachedFull = 0
        for session in sessions where session.startDate >= since {
            count += 1
            if let first = session.samples.first, let last = session.samples.last {
                gained += max(last.level - first.level, 0)
                if last.level >= 0.995 {
                    reachedFull += 1
                }
            }
            if (session.peakThermal?.severity ?? 0) >= 1 {
                heat += 1
            }
            if ChargeAnalyzer.optimizedChargingStatus(session.samples) == .suspected {
                optimized += 1
            }
        }
        return RecentCharging(days: days, count: count, totalGained: gained, heatCount: heat,
                              optimizedCount: optimized, reachedFullCount: reachedFull)
    }
}
