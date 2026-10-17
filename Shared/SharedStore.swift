import Foundation

/// App 与小组件之间通过 App Group 共享最新快照。
enum SharedStore {
    /// 必须与 project.yml 中两个 target 的 entitlements 保持一致
    static let appGroupID = "group.io.github.adrian-0925.phonepulse"
    private static let snapshotKey = "latestSnapshot"

    static func save(_ snapshot: MetricsSnapshot) {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: snapshotKey)
    }

    static func load() -> MetricsSnapshot? {
        guard let data = UserDefaults(suiteName: appGroupID)?.data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder().decode(MetricsSnapshot.self, from: data)
    }
}
