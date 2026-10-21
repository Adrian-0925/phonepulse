import Foundation

/// 一个配件组合（充电器 + 线材），由用户起名，如「床头充电器＋白色线」
struct AccessoryProfile: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var createdAt: Date
}

/// 所有配件组合，以及最近用过的顺序（选择时把常用的放前面，少点几下）
struct AccessoryBook: Codable, Equatable {
    static let maxNameLength = 24

    private(set) var profiles: [AccessoryProfile] = []
    /// 最近用过的在前
    private(set) var recentIDs: [UUID] = []

    init() {}

    /// 最近用过的在前，没用过的按创建时间排在后面
    var sortedByRecent: [AccessoryProfile] {
        let used = recentIDs.compactMap(profile)
        let unused = profiles.filter { !recentIDs.contains($0.id) }.sorted { $0.createdAt > $1.createdAt }
        return used + unused
    }

    var lastUsed: AccessoryProfile? {
        recentIDs.first.flatMap(profile)
    }

    func profile(_ id: UUID) -> AccessoryProfile? {
        profiles.first { $0.id == id }
    }

    /// 新建；名字为空返回 nil，和已有的重名（不分大小写、忽略首尾空格）时直接返回已有的那个
    @discardableResult
    mutating func add(name: String, at date: Date) -> AccessoryProfile? {
        guard let cleaned = Self.clean(name) else { return nil }
        if let existing = profiles.first(where: { $0.name.lowercased() == cleaned.lowercased() }) {
            return existing
        }
        let profile = AccessoryProfile(id: UUID(), name: cleaned, createdAt: date)
        profiles.append(profile)
        return profile
    }

    /// 改名；新名字为空或和别的组合重名时不改，返回 false
    @discardableResult
    mutating func rename(_ id: UUID, to name: String) -> Bool {
        guard let cleaned = Self.clean(name),
              let index = profiles.firstIndex(where: { $0.id == id }),
              !profiles.contains(where: { $0.id != id && $0.name.lowercased() == cleaned.lowercased() }) else { return false }
        profiles[index].name = cleaned
        return true
    }

    mutating func remove(_ id: UUID) {
        profiles.removeAll { $0.id == id }
        recentIDs.removeAll { $0 == id }
    }

    mutating func markUsed(_ id: UUID) {
        guard profile(id) != nil else { return }
        recentIDs.removeAll { $0 == id }
        recentIDs.insert(id, at: 0)
    }

    private static func clean(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(maxNameLength))
    }
}

extension Array where Element == ChargeSession {
    /// 删除配件组合后，把关联到它的记录改回「未指定」（记录本身保留）
    func unlinking(accessory id: UUID) -> [ChargeSession] {
        map { session in
            var session = session
            if session.accessoryID == id {
                session.accessoryID = nil
            }
            return session
        }
    }
}

// MARK: - 对比

/// 一次充电在对比区间里的表现（只用 App 实际在记录的连续数据）
struct RangeRun: Equatable {
    var sessionID: UUID
    var startDate: Date
    /// 从进入区间下限到进入上限用了多久
    var duration: TimeInterval
    /// 电量增长速度（每小时比例）
    var levelPerHour: Double
    /// 估算功率；不知道容量时为 nil
    var watts: Double?
    var peakThermal: ThermalLevel?
}

/// 一个配件组合的统计
struct AccessoryStats: Equatable {
    var accessoryID: UUID
    /// 这个组合的全部记录数
    var sessionCount: Int
    /// 覆盖了对比区间的记录
    var runs: [RangeRun]
    /// 全部记录的常见起止电量和单次用时（中位数）
    var typicalStartLevel: Double?
    var typicalEndLevel: Double?
    var typicalDuration: TimeInterval?

    var medianLevelPerHour: Double? { AccessoryComparison.median(runs.map(\.levelPerHour)) }
    var medianDuration: TimeInterval? { AccessoryComparison.median(runs.map(\.duration)) }
    var medianWatts: Double? { AccessoryComparison.median(runs.compactMap(\.watts)) }
    /// 同一组里最快和最慢差多少（0.3 = 快的比慢的快 30%）
    var spread: Double? {
        let rates = runs.map(\.levelPerHour).filter { $0 > 0 }
        guard rates.count >= 2, let low = rates.min(), let high = rates.max() else { return nil }
        return high / low - 1
    }
}

enum ComparisonVerdict: Equatable {
    /// 数据不足，继续记录
    case insufficient(InsufficientReason)
    /// 两组都有记录，但至少一组只有 1 次：只列数字，不下结论
    case preliminary
    /// 差别在误差范围内
    case similar(difference: Double)
    /// 某一组明显更快
    case faster(accessoryID: UUID, difference: Double)
}

enum InsufficientReason: Equatable {
    /// 这个组合还没有可用的记录
    case noRecords(UUID)
    /// 两组记录没有重合的电量区间
    case noCommonRange
}

/// 两个配件组合的对比：只在两组都覆盖到的同一电量区间里比较，用真实记录的时间和电量变化
struct AccessoryComparison: Equatable {
    /// 区间至少这么宽（10 个百分点）
    static let minimumWidth = 10
    /// 每组至少这么多次记录才下结论
    static let conclusiveRuns = 2
    /// 快慢差别小于这个比例算「差不多」（估算误差和日常波动大约在这个量级）
    static let similarThreshold = 0.10
    /// 优先比较这个电量以下的区间，避开 80% 以后系统放慢充电
    static let preferredCeiling = 80

    /// 对比区间（百分比，如 30...60）；没有重合区间时为 nil
    var range: ClosedRange<Int>?
    var a: AccessoryStats
    var b: AccessoryStats
    var verdict: ComparisonVerdict

    /// 参与对比的记录里有发热（温控偏高及以上）的
    var hadHeat: Bool {
        (a.runs + b.runs).contains { ($0.peakThermal?.severity ?? 0) >= 1 }
    }

    static func compare(_ first: UUID, _ second: UUID, sessions: [ChargeSession]) -> AccessoryComparison {
        let sessionsA = sessions.filter { $0.accessoryID == first }
        let sessionsB = sessions.filter { $0.accessoryID == second }
        let entriesA: [[Int: (time: Date, segment: Int)]] = sessionsA.map { entries(of: $0) }
        let entriesB: [[Int: (time: Date, segment: Int)]] = sessionsB.map { entries(of: $0) }

        let range = bestRange(entriesA, entriesB)
        var statsA = summary(first, sessions: sessionsA)
        var statsB = summary(second, sessions: sessionsB)
        if let range {
            statsA.runs = zip(sessionsA, entriesA).compactMap { run($0.0, entries: $0.1, range: range) }
            statsB.runs = zip(sessionsB, entriesB).compactMap { run($0.0, entries: $0.1, range: range) }
        }

        let verdict: ComparisonVerdict
        if sessionsA.isEmpty {
            verdict = .insufficient(.noRecords(first))
        } else if sessionsB.isEmpty {
            verdict = .insufficient(.noRecords(second))
        } else if range == nil || statsA.runs.isEmpty || statsB.runs.isEmpty {
            verdict = .insufficient(.noCommonRange)
        } else if statsA.runs.count < conclusiveRuns || statsB.runs.count < conclusiveRuns {
            verdict = .preliminary
        } else if let rateA = statsA.medianLevelPerHour, let rateB = statsB.medianLevelPerHour, rateA > 0, rateB > 0 {
            let ratio = max(rateA, rateB) / min(rateA, rateB) - 1
            if ratio < similarThreshold {
                verdict = .similar(difference: ratio)
            } else {
                verdict = .faster(accessoryID: rateA > rateB ? first : second, difference: ratio)
            }
        } else {
            verdict = .insufficient(.noCommonRange)
        }
        return AccessoryComparison(range: range, a: statsA, b: statsB, verdict: verdict)
    }

    // MARK: - 计算

    /// 某次充电「刚涨到」每个整数百分比的时刻，以及属于哪一段连续数据。
    /// 只取「上一个点电量更低、且和上一个点间隔不超过连续性上限」的点，所以时间是 App 实际看到的变化时刻
    static func entries(of session: ChargeSession) -> [Int: (time: Date, segment: Int)] {
        var result: [Int: (time: Date, segment: Int)] = [:]
        var segment = 0
        let samples = session.samples
        for index in samples.indices.dropFirst() {
            let previous = samples[index - 1]
            let sample = samples[index]
            guard sample.time.timeIntervalSince(previous.time) <= ChargeSessionRecorder.continuityLimit else {
                segment += 1
                continue
            }
            let from = percent(previous.level)
            let to = percent(sample.level)
            guard to > from else { continue }
            for value in (from + 1)...to where result[value] == nil {
                result[value] = (sample.time, segment)
            }
        }
        return result
    }

    /// 两组都尽量有记录覆盖的区间：先看覆盖的记录数（最多算到 conclusiveRuns），再优先 80% 以下，再看宽度
    static func bestRange(_ groupA: [[Int: (time: Date, segment: Int)]], _ groupB: [[Int: (time: Date, segment: Int)]]) -> ClosedRange<Int>? {
        guard !groupA.isEmpty, !groupB.isEmpty else { return nil }
        var bestRange: ClosedRange<Int>?
        var bestScore: [Int] = []
        for low in 1...(100 - minimumWidth) {
            for high in (low + minimumWidth)...100 {
                let countA = groupA.filter { covers($0, low: low, high: high) }.count
                let countB = groupB.filter { covers($0, low: low, high: high) }.count
                let covered = min(countA, countB, conclusiveRuns)
                guard covered > 0 else { continue }
                let score: [Int] = [covered, high <= preferredCeiling ? 1 : 0, high - low, min(countA, countB)]
                // 分数更高才替换；分数相同保留先找到的（电量更低的区间）
                if bestRange == nil || bestScore.lexicographicallyPrecedes(score) {
                    bestRange = low...high
                    bestScore = score
                }
            }
        }
        return bestRange
    }

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count % 2 == 0 ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    /// 这次充电在同一段连续数据里，先后涨到了 low 和 high
    static func covers(_ entries: [Int: (time: Date, segment: Int)], low: Int, high: Int) -> Bool {
        guard let start = entries[low], let end = entries[high] else { return false }
        return start.segment == end.segment && end.time > start.time
    }

    /// 这次充电在 range 区间里的表现；没有完整覆盖时为 nil。「和平时比」（ChargeInsights）也用它
    static func run(_ session: ChargeSession, entries: [Int: (time: Date, segment: Int)], range: ClosedRange<Int>) -> RangeRun? {
        guard covers(entries, low: range.lowerBound, high: range.upperBound),
              let start = entries[range.lowerBound], let end = entries[range.upperBound] else { return nil }
        let duration = end.time.timeIntervalSince(start.time)
        let rate = Double(range.upperBound - range.lowerBound) / 100 / duration * 3600
        var watts: Double?
        if let capacity = session.capacityMAh, capacity > 0 {
            watts = BatteryPowerEstimator.watts(levelPerHour: rate, capacityMAh: capacity)
        }
        return RangeRun(sessionID: session.id, startDate: session.startDate, duration: duration, levelPerHour: rate, watts: watts, peakThermal: session.peakThermal)
    }

    private static func summary(_ id: UUID, sessions: [ChargeSession]) -> AccessoryStats {
        let starts = sessions.compactMap { $0.samples.first?.level }
        let ends = sessions.compactMap { $0.samples.last?.level }
        let durations = sessions.compactMap { session -> TimeInterval? in
            guard let end = session.endDate else { return nil }
            return end.timeIntervalSince(session.startDate)
        }
        return AccessoryStats(
            accessoryID: id,
            sessionCount: sessions.count,
            runs: [],
            typicalStartLevel: median(starts),
            typicalEndLevel: median(ends),
            typicalDuration: median(durations))
    }

    /// 电量（0...1）换成整数百分比，和界面显示的取整方式一致
    private static func percent(_ level: Double) -> Int {
        Int((min(max(level, 0), 1) * 100).rounded())
    }
}
