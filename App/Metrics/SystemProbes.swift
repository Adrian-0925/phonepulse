import Foundation

enum AppSettings {
    /// 用户自定义的电池容量（mAh），0 表示使用机型内置数据
    static let batteryCapacityKey = "batteryCapacityOverride"
}

enum StorageProbe {
    static func sample() -> StorageSample? {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        guard let values = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]),
              let total = values.volumeTotalCapacity,
              let available = values.volumeAvailableCapacityForImportantUsage else { return nil }
        return StorageSample(totalBytes: Int64(total), availableBytes: available)
    }
}

extension ThermalLevel {
    init(_ state: ProcessInfo.ThermalState) {
        switch state {
        case .nominal: self = .nominal
        case .fair: self = .fair
        case .serious: self = .serious
        case .critical: self = .critical
        @unknown default: self = .nominal
        }
    }
}
