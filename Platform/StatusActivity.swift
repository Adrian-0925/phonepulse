import ActivityKit
import SwiftUI

/// 灵动岛收起时重点显示什么
enum LiveActivityFocus: String, Codable, Hashable, CaseIterable {
    /// 插着电时看电池，否则看网速
    case auto
    case charging
    case network
    case performance

    var label: String {
        switch self {
        case .auto: "自动"
        case .charging: "电池"
        case .network: "网速"
        case .performance: "性能"
        }
    }
}

/// 灵动岛 / 锁屏实时活动的数据。所有内容都在 ContentState 里，切换显示内容不需要重新开启。
struct StatusActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var focus: LiveActivityFocus
        var batteryLevel: Double?
        var batteryState: BatteryState
        /// 估算
        var powerWatts: Double?
        /// 估算，每小时变化的比例
        var levelPerHour: Double?
        /// 估算的充满时间；系统会让倒计时和进度条自己走动，不需要 App 更新
        var fullDate: Date?
        var downloadBytesPerSecond: Double
        var uploadBytesPerSecond: Double
        /// 整机 CPU 使用率；系统不开放时为 nil
        var cpuUsage: Double?
        var thermal: ThermalLevel
        var updatedAt: Date
        /// App 正在采样（前台或悬浮窗开着）；false 表示显示的是最后一次的数据
        var isLive: Bool
        /// 这份数据来自灵动岛上的「刷新」按钮（App 被暂停时现场读了一次），之后不会自动更新
        var manualRefresh: Bool? = nil
        /// 功率测定到哪一步（正在采集 / 初步 / 较稳定 / 已放缓）；旧版本推送的数据里没有
        var powerPhase: PowerPhase? = nil

        /// 状态行文字
        var statusText: String {
            if isLive { return "实时" }
            return manualRefresh == true ? "手动刷新" : "已暂停"
        }

        var effectiveFocus: LiveActivityFocus {
            guard focus == .auto else { return focus }
            return batteryState.isPluggedIn ? .charging : .network
        }

        var batteryText: String {
            batteryLevel.map(Format.batteryPercent) ?? "--"
        }

        var accentColor: Color {
            switch effectiveFocus {
            case .auto, .charging: Theme.batteryColor(level: batteryLevel, state: batteryState)
            case .network: Theme.network
            case .performance: Theme.cpu
            }
        }
    }
}

extension StatusActivityAttributes.ContentState {
    /// 界面上实际显示出来的内容（按显示精度取整）。和上次推送的一样就不用再推，省电也避免被系统限流
    var displaySignature: [String] {
        [
            focus.rawValue,
            batteryText,
            batteryState.rawValue,
            powerWatts.map(Format.estimatedWattsNumber) ?? "-",
            levelPerHour.map { String(format: "%.2f", $0) } ?? "-",
            Format.speed(downloadBytesPerSecond),
            Format.speed(uploadBytesPerSecond),
            cpuUsage.map { String(format: "%.0f", $0 * 100) } ?? "-",
            thermal.rawValue,
            fullDate.map { String(Int($0.timeIntervalSinceReferenceDate / 60)) } ?? "-",
            statusText,
            powerPhase?.rawValue ?? "-",
        ]
    }

    /// 由一次现场读数生成（灵动岛「刷新」按钮在 App 被暂停时用）。
    /// 充电速度、功率和充满时间没法现场测，插电状态没变时沿用上一次的估算
    init(reading: InstantReading, focus: LiveActivityFocus, previous: Self?) {
        let samePlugState = previous?.batteryState.isPluggedIn == reading.battery.state.isPluggedIn
        self.init(
            focus: focus,
            batteryLevel: reading.battery.level,
            batteryState: reading.battery.state,
            powerWatts: samePlugState ? previous?.powerWatts : nil,
            levelPerHour: samePlugState ? previous?.levelPerHour : nil,
            fullDate: samePlugState && reading.battery.state == .charging ? previous?.fullDate : nil,
            downloadBytesPerSecond: reading.network.downloadBytesPerSecond,
            uploadBytesPerSecond: reading.network.uploadBytesPerSecond,
            cpuUsage: reading.cpu?.usage,
            thermal: reading.thermal,
            updatedAt: .now,
            isLive: false,
            manualRefresh: true,
            powerPhase: samePlugState ? previous?.powerPhase : nil)
    }

    /// 由 App 的一次完整采样生成
    init(snapshot: MetricsSnapshot, focus: LiveActivityFocus, isLive: Bool) {
        let battery = snapshot.battery
        var fullDate: Date?
        if battery.state == .charging, let level = battery.level, let rate = battery.levelPerHour,
           let seconds = ChargeForecast.timeToFull(level: level, levelPerHour: rate) {
            fullDate = snapshot.timestamp.addingTimeInterval(seconds)
        }
        self.init(
            focus: focus,
            batteryLevel: battery.level,
            batteryState: battery.state,
            powerWatts: battery.estimatedPowerWatts,
            levelPerHour: battery.levelPerHour,
            fullDate: fullDate,
            downloadBytesPerSecond: snapshot.network.downloadBytesPerSecond,
            uploadBytesPerSecond: snapshot.network.uploadBytesPerSecond,
            cpuUsage: snapshot.cpu?.isSystemWide == true ? snapshot.cpu?.usage : nil,
            thermal: snapshot.thermal,
            updatedAt: snapshot.timestamp,
            isLive: isLive,
            manualRefresh: nil,
            powerPhase: battery.power?.phase)
    }
}
