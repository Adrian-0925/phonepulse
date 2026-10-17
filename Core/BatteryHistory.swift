import Foundation

struct BatteryPoint: Codable, Equatable {
    var time: Date
    var level: Double
    /// 插着电（充电中或已充满）
    var isCharging: Bool
}

/// 电量历史。小组件每次刷新记一个点（App 不运行时也能积累），用来画电量曲线和推算充电/耗电速度。
struct BatteryHistory: Codable, Equatable {
    /// 只保留最近 24 小时
    static let retention: TimeInterval = 24 * 3600
    /// 两个点间隔太短时只保留新的那个
    static let minimumInterval: TimeInterval = 60

    private(set) var points: [BatteryPoint]

    init(points: [BatteryPoint] = []) {
        self.points = points
    }

    mutating func append(_ point: BatteryPoint) {
        if let last = points.last, point.time.timeIntervalSince(last.time) < Self.minimumInterval {
            points[points.count - 1] = point
        } else {
            points.append(point)
        }
        points.removeAll { point.time.timeIntervalSince($0.time) > Self.retention }
    }

    /// 最近一段"插电状态没变过"的电量变化速度（每小时变化的比例）。跨度不足 minimumSpan 时返回 nil。
    func recentLevelPerHour(maxSpan: TimeInterval = 2 * 3600, minimumSpan: TimeInterval = 10 * 60) -> Double? {
        guard let last = points.last else { return nil }
        var first = last
        for point in points.reversed() {
            guard point.isCharging == last.isCharging,
                  last.time.timeIntervalSince(point.time) <= maxSpan else { break }
            first = point
        }
        let span = last.time.timeIntervalSince(first.time)
        guard span >= minimumSpan else { return nil }
        return (last.level - first.level) / span * 3600
    }
}
