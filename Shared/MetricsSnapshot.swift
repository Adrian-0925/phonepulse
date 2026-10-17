import Foundation

/// 一次采样得到的完整设备状态。App 每秒生成一份，小组件读取最近保存的一份。
struct MetricsSnapshot: Codable, Equatable {
    var timestamp: Date
    var network: NetworkSample
    var cpu: CPUSample?
    var memory: MemorySample?
    var battery: BatterySample
    var storage: StorageSample?
    var thermal: ThermalLevel
}

struct NetworkSample: Codable, Equatable {
    var downloadBytesPerSecond: Double
    var uploadBytesPerSecond: Double
    /// 本次打开 App 以来经过 Wi-Fi / 蜂窝的总流量（收 + 发）
    var sessionWifiBytes: UInt64
    var sessionCellularBytes: UInt64
    var connection: ConnectionType
}

enum ConnectionType: String, Codable {
    case wifi, cellular, wired, other, none

    var label: String {
        switch self {
        case .wifi: "Wi-Fi"
        case .cellular: "蜂窝"
        case .wired: "有线"
        case .other: "其他"
        case .none: "未连接"
        }
    }
}

struct CPUSample: Codable, Equatable {
    /// 0...1
    var usage: Double
    var user: Double
    var system: Double
    /// false 表示系统不允许读整机数据，只统计了本 App 进程
    var isSystemWide: Bool
    var coreCount: Int
}

struct MemorySample: Codable, Equatable {
    var totalBytes: UInt64
    var usedBytes: UInt64
    var appFootprintBytes: UInt64

    var usedFraction: Double { totalBytes == 0 ? 0 : Double(usedBytes) / Double(totalBytes) }
}

struct BatterySample: Codable, Equatable {
    /// 0...1；模拟器上为 nil
    var level: Double?
    var state: BatteryState
    var isLowPowerMode: Bool
    /// 估算的电池净功率（瓦），正数为充入、负数为放电；采样不足时为 nil
    var estimatedPowerWatts: Double?
    var capacityMAh: Int?
}

enum BatteryState: String, Codable {
    case unknown, unplugged, charging, full

    var label: String {
        switch self {
        case .unknown: "未知"
        case .unplugged: "未充电"
        case .charging: "充电中"
        case .full: "已充满"
        }
    }
}

struct StorageSample: Codable, Equatable {
    var totalBytes: Int64
    var availableBytes: Int64

    var usedFraction: Double { totalBytes == 0 ? 0 : Double(totalBytes - availableBytes) / Double(totalBytes) }
}

/// iOS 只公开 4 档温度状态，没有具体摄氏度
enum ThermalLevel: String, Codable {
    case nominal, fair, serious, critical

    var label: String {
        switch self {
        case .nominal: "正常"
        case .fair: "偏高"
        case .serious: "高"
        case .critical: "严重"
        }
    }
}

extension MetricsSnapshot {
    /// 小组件预览和占位用的假数据
    static let placeholder = MetricsSnapshot(
        timestamp: .now,
        network: NetworkSample(
            downloadBytesPerSecond: 1_200_000,
            uploadBytesPerSecond: 85_000,
            sessionWifiBytes: 0,
            sessionCellularBytes: 0,
            connection: .wifi),
        cpu: CPUSample(usage: 0.23, user: 0.15, system: 0.08, isSystemWide: true, coreCount: 6),
        memory: MemorySample(totalBytes: 6 << 30, usedBytes: 4 << 30, appFootprintBytes: 80 << 20),
        battery: BatterySample(level: 0.76, state: .charging, isLowPowerMode: false, estimatedPowerWatts: 15.2, capacityMAh: 3274),
        storage: StorageSample(totalBytes: 128_000_000_000, availableBytes: 42_000_000_000),
        thermal: .nominal)
}
