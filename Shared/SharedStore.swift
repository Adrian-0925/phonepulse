import Foundation

/// App 与小组件之间通过 App Group 共享数据。
/// 免费账号侧载时 App Group 不可用：两边各自读写自己的存储，App 本身不受影响，只是小组件读不到 App 里填写的设置。
enum SharedStore {
    /// 必须与 project.yml 中两个 target 的 entitlements 保持一致
    static let appGroupID = "group.io.github.adrian-0925.phonepulse"

    enum Key {
        static let snapshot = "latestSnapshot"
        static let batteryCapacityOverride = "batteryCapacityOverride"
        static let batteryHealthPercent = "batteryHealthPercent"
        static let batteryCycleCount = "batteryCycleCount"
        static let liveActivityFocus = "liveActivityFocus"
    }

    static let defaults: UserDefaults = UserDefaults(suiteName: appGroupID) ?? .standard

    static func save(_ snapshot: MetricsSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: Key.snapshot)
    }

    static func load() -> MetricsSnapshot? {
        guard let data = defaults.data(forKey: Key.snapshot) else { return nil }
        return try? JSONDecoder().decode(MetricsSnapshot.self, from: data)
    }
}
