import Foundation

struct ChargeSample: Codable, Equatable {
    var time: Date
    var level: Double
}

/// 一次充电：从插电到拔电。
/// App 只在运行时能看到数据，所以插电、拔电的那一刻不一定被看到，用 startObserved / endObserved 如实记录。
struct ChargeSession: Codable, Equatable, Identifiable {
    var id: UUID
    /// 第一次看到插着电的时间；startObserved 为 false 时，真实插电时间更早
    var startDate: Date
    /// nil 表示还在充电
    var endDate: Date?
    /// 看到了从"没插电"变成"插电"的那一刻
    var startObserved: Bool
    /// 看到了拔电的那一刻
    var endObserved: Bool
    /// 约每分钟一个点，电量变化时也记
    var samples: [ChargeSample]
    /// 充电器标签（如「原装 20W」），给充电器对比用
    var tag: String?
    /// 当时的满电容量，用来把速度换算成估算功率
    var capacityMAh: Int?
    /// 这次用的配件组合（AccessoryBook 里的 id）；nil 表示没指定
    var accessoryID: UUID? = nil
    /// 这次充电期间最高的温控状态：发热会让系统放慢充电，对比时要提醒
    var peakThermal: ThermalLevel? = nil

    var isOngoing: Bool { endDate == nil }
}

/// 把每秒的电量读数整理成一次次充电记录。纯计算，时间由调用方传入，方便单元测试。
struct ChargeSessionRecorder: Codable, Equatable {
    /// 两次读数间隔超过这个值，就算中间缺了数据
    static let continuityLimit: TimeInterval = 150
    /// 正在充电时至少每隔这么久记一个点（电量变化时也会记）
    static let sampleInterval: TimeInterval = 60
    /// App 没运行的这段时间里电量掉了这么多，说明中间拔过电，算新的一次充电
    static let replugDrop: Double = 0.02

    private(set) var current: ChargeSession?
    private var lastState: BatteryState?
    private var lastTime: Date?

    init() {}

    /// 给正在进行的充电指定配件组合
    mutating func assignAccessory(_ id: UUID?) {
        current?.accessoryID = id
    }

    /// 每次读到电量时调用；拔电（或发现中间拔过电）时返回刚结束的那次充电
    @discardableResult
    mutating func record(level: Double?, state: BatteryState, at time: Date, capacityMAh: Int?, thermal: ThermalLevel? = nil) -> ChargeSession? {
        guard state != .unknown, let level else { return nil }
        let continuous = lastTime.map { time.timeIntervalSince($0) <= Self.continuityLimit } ?? false
        let previousState = lastState
        lastState = state
        lastTime = time

        var finished: ChargeSession?
        if state.isPluggedIn {
            if var session = current, !continuous, let last = session.samples.last, level < last.level - Self.replugDrop {
                // App 没运行期间电量掉了，说明中间拔过电：上一次充电只能算到最后一个点
                session.endDate = last.time
                session.endObserved = false
                finished = session
                current = nil
            }
            if var session = current {
                if let last = session.samples.last,
                   last.level != level || time.timeIntervalSince(last.time) >= Self.sampleInterval {
                    session.samples.append(ChargeSample(time: time, level: level))
                }
                if let capacityMAh {
                    session.capacityMAh = capacityMAh
                }
                session.peakThermal = Self.hotter(session.peakThermal, thermal)
                current = session
            } else {
                current = ChargeSession(
                    id: UUID(),
                    startDate: time,
                    endDate: nil,
                    startObserved: continuous && previousState?.isPluggedIn == false,
                    endObserved: false,
                    samples: [ChargeSample(time: time, level: level)],
                    tag: nil,
                    capacityMAh: capacityMAh,
                    peakThermal: thermal)
            }
        } else if var session = current {
            // 拔电：看到了拔电那一刻就记当前时间，否则只能算到最后一个点
            if continuous {
                session.samples.append(ChargeSample(time: time, level: level))
                session.endDate = time
            } else {
                session.endDate = session.samples.last?.time ?? time
            }
            session.endObserved = continuous
            finished = session
            current = nil
        }
        return finished
    }

    /// 快捷指令自动化「充电器已连接」时调用：这一刻确实刚插上电，所以开始时间是准的（startObserved）。
    /// App 正在记录这次充电时什么都不做；有一条很久没更新的旧记录（当时没看到拔电）就先结束它，再从这一刻开始新的一次。
    /// 返回被结束的旧记录
    @discardableResult
    mutating func recordPlugIn(level: Double?, at time: Date, capacityMAh: Int?, thermal: ThermalLevel? = nil) -> ChargeSession? {
        guard let level else { return nil }
        let continuous = lastTime.map { time.timeIntervalSince($0) <= Self.continuityLimit } ?? false
        if current != nil, continuous, lastState?.isPluggedIn == true {
            return nil
        }
        var finished: ChargeSession?
        if var session = current {
            session.endDate = session.samples.last?.time ?? session.startDate
            session.endObserved = false
            finished = session
        }
        current = ChargeSession(
            id: UUID(),
            startDate: time,
            endDate: nil,
            startObserved: true,
            endObserved: false,
            samples: [ChargeSample(time: time, level: level)],
            tag: nil,
            capacityMAh: capacityMAh,
            peakThermal: thermal)
        lastState = .charging
        lastTime = time
        return finished
    }

    /// 快捷指令自动化「充电器已断开」时调用：以这一刻结束正在进行的充电（endObserved）。
    /// 中间 App 没运行，所以只多一个结束点：起止时间和电量是准的，平均速度可信，中间的曲线没有。
    /// 返回结束的记录；没有正在进行的充电时返回 nil
    @discardableResult
    mutating func recordUnplug(level: Double?, at time: Date) -> ChargeSession? {
        lastState = .unplugged
        lastTime = time
        guard var session = current else { return nil }
        current = nil
        if let level, let last = session.samples.last, level < last.level - Self.replugDrop {
            // 电量比上次记录时还低：中间拔过电（当时没记录到），这次充电只能算到最后一个点
            session.endDate = last.time
            session.endObserved = false
        } else {
            if let level {
                session.samples.append(ChargeSample(time: time, level: level))
            }
            session.endDate = time
            session.endObserved = true
        }
        return session
    }

    private static func hotter(_ a: ThermalLevel?, _ b: ThermalLevel?) -> ThermalLevel? {
        guard let a else { return b }
        guard let b else { return a }
        return b.severity > a.severity ? b : a
    }
}

enum OptimizedChargingStatus: Equatable {
    /// 到 80% 左右后明显放慢，疑似系统的优化充电
    case suspected
    case notDetected
    /// 没充到 80% 附近，或那段时间没有数据
    case insufficientData
}

/// 单次充电报告
struct ChargeReport: Equatable {
    var startLevel: Double
    var endLevel: Double
    var duration: TimeInterval
    /// 平均电量变化速度（每小时比例）；数据太少时为 nil
    var levelPerHour: Double?
    var averageWatts: Double?
    var peakWatts: Double?
    /// 0...1：这段时间里有多少比例是 App 实际在记录的
    var completeness: Double
    var optimizedCharging: OptimizedChargingStatus
}

enum ChargeAnalyzer {
    /// 峰值功率按至少这么长的时间窗口计算，避免电量取整造成的跳动
    static let peakWindow: TimeInterval = 10 * 60
    /// 到 80% 后至少放慢这么久才算疑似优化充电
    static let holdDuration: TimeInterval = 20 * 60

    static func report(for session: ChargeSession, now: Date) -> ChargeReport? {
        guard let first = session.samples.first, let last = session.samples.last else { return nil }
        let end = session.endDate ?? now
        let span = last.time.timeIntervalSince(first.time)
        var rate: Double?
        if span >= 5 * 60, abs(last.level - first.level) >= 0.02 {
            rate = (last.level - first.level) / span * 3600
        }
        let peakRate = peakLevelPerHour(session.samples)
        return ChargeReport(
            startLevel: first.level,
            endLevel: last.level,
            duration: max(end.timeIntervalSince(session.startDate), 0),
            levelPerHour: rate,
            averageWatts: watts(rate, capacity: session.capacityMAh),
            peakWatts: watts(peakRate, capacity: session.capacityMAh),
            completeness: completeness(session.samples, start: session.startDate, end: end),
            optimizedCharging: optimizedChargingStatus(session.samples))
    }

    /// [start, end] 这段时间里，相邻读数间隔不超过 continuityLimit 的部分所占比例
    static func completeness(_ samples: [ChargeSample], start: Date, end: Date) -> Double {
        let total = end.timeIntervalSince(start)
        guard total > 0, let first = samples.first, let last = samples.last else { return 0 }
        let limit = ChargeSessionRecorder.continuityLimit
        var covered: TimeInterval = 0
        let head = first.time.timeIntervalSince(start)
        if head <= limit {
            covered += max(head, 0)
        }
        for index in samples.indices.dropFirst() {
            let gap = samples[index].time.timeIntervalSince(samples[index - 1].time)
            if gap <= limit {
                covered += gap
            }
        }
        let tail = end.timeIntervalSince(last.time)
        if tail <= limit {
            covered += max(tail, 0)
        }
        return min(covered / total, 1)
    }

    /// 任意连续 window 时长内的最大电量变化速度（只用电量发生变化的点）
    static func peakLevelPerHour(_ samples: [ChargeSample], window: TimeInterval = peakWindow) -> Double? {
        var points: [ChargeSample] = []
        for sample in samples where points.last?.level != sample.level {
            points.append(sample)
        }
        var best: Double?
        var end = 0
        for start in points.indices {
            end = max(end, start)
            while end < points.count, points[end].time.timeIntervalSince(points[start].time) < window {
                end += 1
            }
            guard end < points.count else { break }
            let rate = (points[end].level - points[start].level) / points[end].time.timeIntervalSince(points[start].time) * 3600
            best = max(best ?? rate, rate)
        }
        return best
    }

    /// 到 79% 后至少 20 分钟没超过 82%，且这段速度不到之前的三分之一
    static func optimizedChargingStatus(_ samples: [ChargeSample]) -> OptimizedChargingStatus {
        guard let first = samples.first, first.level < 0.75,
              let reach = samples.firstIndex(where: { $0.level >= 0.79 }),
              let last = samples.last else { return .insufficientData }
        let reachSample = samples[reach]
        let earlierSpan = reachSample.time.timeIntervalSince(first.time)
        guard earlierSpan >= 10 * 60, last.time.timeIntervalSince(reachSample.time) >= holdDuration else { return .insufficientData }

        let held = samples[reach...].prefix { $0.level <= 0.82 }
        guard let lastHeld = held.last else { return .notDetected }
        let holdSpan = lastHeld.time.timeIntervalSince(reachSample.time)
        guard holdSpan >= holdDuration else { return .notDetected }

        let earlierRate = (reachSample.level - first.level) / earlierSpan * 3600
        let holdRate = (lastHeld.level - reachSample.level) / holdSpan * 3600
        return holdRate <= earlierRate / 3 ? .suspected : .notDetected
    }

    private static func watts(_ levelPerHour: Double?, capacity: Int?) -> Double? {
        guard let levelPerHour, let capacity, capacity > 0 else { return nil }
        return BatteryPowerEstimator.watts(levelPerHour: levelPerHour, capacityMAh: capacity)
    }
}
