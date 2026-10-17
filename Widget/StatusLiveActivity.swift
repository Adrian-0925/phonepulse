import ActivityKit
import SwiftUI
import WidgetKit

private typealias ActivityState = StatusActivityAttributes.ContentState

/// 灵动岛 + 锁屏实时活动的界面。
/// 收起时只显示一个重点（电池 / 网速 / 性能），展开后看全部；充满倒计时和进度条由系统自己走动。
struct StatusLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: StatusActivityAttributes.self) { context in
            LockScreenActivityView(state: context.state, isStale: context.isStale)
                .activityBackgroundTint(Color(red: 0.06, green: 0.06, blue: 0.11).opacity(0.94))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    BatteryHeadline(state: state)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    FocusHeadline(state: state)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ActivityDetails(state: state, isStale: context.isStale)
                        .padding(.horizontal, 4)
                }
            } compactLeading: {
                CompactLeadingView(state: state)
            } compactTrailing: {
                CompactTrailingView(state: state)
            } minimal: {
                MinimalActivityView(state: state)
            }
            .keylineTint(state.accentColor)
        }
    }
}

// MARK: - 锁屏

private struct LockScreenActivityView: View {
    let state: ActivityState
    let isStale: Bool

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                BatteryHeadline(state: state)
                Spacer(minLength: 0)
                FocusHeadline(state: state)
            }
            ActivityDetails(state: state, isStale: isStale)
        }
        .padding(14)
    }
}

// MARK: - 灵动岛收起

private struct CompactLeadingView: View {
    let state: ActivityState

    var body: some View {
        Group {
            switch state.effectiveFocus {
            case .auto, .charging:
                HStack(spacing: 3) {
                    Image(systemName: state.batteryState == .charging ? "bolt.fill" : "battery.100percent")
                        .foregroundStyle(state.accentColor)
                    Text(state.batteryText)
                }
            case .network:
                HStack(spacing: 2) {
                    Image(systemName: "arrow.down")
                        .foregroundStyle(Theme.network)
                    Text(Format.compactSpeed(state.downloadBytesPerSecond))
                }
            case .performance:
                HStack(spacing: 3) {
                    Image(systemName: "cpu")
                        .foregroundStyle(Theme.cpu)
                    Text(state.cpuText)
                }
            }
        }
        .font(.system(size: 14, weight: .semibold, design: .rounded))
        .monospacedDigit()
        .foregroundStyle(.white)
    }
}

private struct CompactTrailingView: View {
    let state: ActivityState

    var body: some View {
        Group {
            switch state.effectiveFocus {
            case .auto, .charging:
                if state.batteryState == .charging, let end = state.countdownEnd {
                    // 充满倒计时由系统自己走动，App 不运行也会更新
                    Text(timerInterval: state.updatedAt...end, countsDown: true)
                        .frame(width: 48)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(Theme.charging)
                } else if let watts = state.powerWatts, watts > 0 {
                    Text(String(format: "%.0fW", watts))
                        .foregroundStyle(Theme.charging)
                } else {
                    Text(state.batteryState == .full ? "已满" : state.batteryState.label)
                }
            case .network:
                HStack(spacing: 2) {
                    Image(systemName: "arrow.up")
                        .foregroundStyle(Theme.upload)
                    Text(Format.compactSpeed(state.uploadBytesPerSecond))
                }
            case .performance:
                Image(systemName: "thermometer.medium")
                    .foregroundStyle(Theme.thermalColor(state.thermal))
            }
        }
        .font(.system(size: 14, weight: .semibold, design: .rounded))
        .monospacedDigit()
        .foregroundStyle(.white)
    }
}

private struct MinimalActivityView: View {
    let state: ActivityState

    var body: some View {
        switch state.effectiveFocus {
        case .auto, .charging:
            RingGauge(progress: state.batteryLevel ?? 0, tint: state.accentColor, lineWidth: 2.5) {
                Image(systemName: state.batteryState == .charging ? "bolt.fill" : "battery.100percent")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(state.accentColor)
            }
        case .network:
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.network)
        case .performance:
            Text(state.cpuText)
                .font(Theme.number(11))
                .foregroundStyle(Theme.cpu)
        }
    }
}

// MARK: - 展开 / 锁屏共用

/// 左上：电量环 + 百分比
private struct BatteryHeadline: View {
    let state: ActivityState

    var body: some View {
        let color = Theme.batteryColor(level: state.batteryLevel, state: state.batteryState)
        HStack(spacing: 8) {
            RingGauge(progress: state.batteryLevel ?? 0, tint: color, lineWidth: 5) {
                Image(systemName: state.batteryState == .charging ? "bolt.fill" : "battery.100percent")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(color)
            }
            .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 0) {
                Text(state.batteryText)
                    .font(Theme.number(22))
                    .foregroundStyle(.white)
                Text(state.batteryState.label)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }
}

/// 右上：当前重点的主数值
private struct FocusHeadline: View {
    let state: ActivityState

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            switch state.effectiveFocus {
            case .auto, .charging:
                Text(state.powerText)
                    .font(Theme.number(20))
                    .foregroundStyle(.white)
                Text(state.powerCaption)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
            case .network:
                Text("↓ \(Format.speed(state.downloadBytesPerSecond))")
                    .font(Theme.number(17))
                    .foregroundStyle(Theme.network)
                Text("↑ \(Format.speed(state.uploadBytesPerSecond))")
                    .font(Theme.number(13, weight: .semibold))
                    .foregroundStyle(Theme.upload)
            case .performance:
                Text(state.cpuText)
                    .font(Theme.number(20))
                    .foregroundStyle(.white)
                Text("CPU 整机使用率")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }
}

/// 下方：充满倒计时 + 四项小数据 + 状态行
private struct ActivityDetails: View {
    let state: ActivityState
    let isStale: Bool

    var body: some View {
        VStack(spacing: 8) {
            if state.batteryState == .charging, let end = state.countdownEnd {
                VStack(spacing: 3) {
                    HStack {
                        Text("预计 \(Text(end, style: .time)) 充满")
                        Spacer()
                        Text(timerInterval: state.updatedAt...end, countsDown: true)
                            .multilineTextAlignment(.trailing)
                    }
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
                    ProgressView(timerInterval: state.updatedAt...end, countsDown: false) {
                        EmptyView()
                    } currentValueLabel: {
                        EmptyView()
                    }
                    .tint(Theme.charging)
                }
            }
            HStack(spacing: 0) {
                StatPill(icon: "arrow.down", value: Format.compactSpeed(state.downloadBytesPerSecond), tint: Theme.network)
                StatPill(icon: "arrow.up", value: Format.compactSpeed(state.uploadBytesPerSecond), tint: Theme.upload)
                StatPill(icon: "cpu", value: state.cpuText, tint: Theme.cpu)
                StatPill(icon: "thermometer.medium", value: state.thermal.label, tint: Theme.thermalColor(state.thermal))
            }
            HStack(spacing: 4) {
                Circle()
                    .fill(state.isLive && !isStale ? Theme.battery : Theme.caution)
                    .frame(width: 6, height: 6)
                Text(statusText)
                Spacer(minLength: 4)
                Text("\(Text(state.updatedAt, style: .time)) 更新")
            }
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .foregroundStyle(Theme.textSecondary)
            .lineLimit(1)
        }
    }

    private var statusText: String {
        if isStale { return "数据可能已过期，打开 App 刷新" }
        return state.isLive ? "实时" : "已暂停 · 打开 App 恢复实时"
    }
}

private struct StatPill: View {
    let icon: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .foregroundStyle(tint)
            Text(value)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .font(.system(size: 12, weight: .semibold, design: .rounded))
        .monospacedDigit()
        .frame(maxWidth: .infinity)
    }
}

private extension StatusActivityAttributes.ContentState {
    var cpuText: String {
        cpuUsage.map { String(format: "%.0f%%", $0 * 100) } ?? "--"
    }

    var powerText: String {
        guard let watts = powerWatts else { return "-- W" }
        return String(format: "≈%.1f W", abs(watts))
    }

    var powerCaption: String {
        guard let watts = powerWatts else { return batteryState == .charging ? "功率估算中" : "耗电功率估算中" }
        return watts >= 0 ? "充电功率（估算）" : "耗电功率（估算）"
    }

    /// 倒计时终点，保证晚于更新时间（区间不合法会让界面崩溃）
    var countdownEnd: Date? {
        guard let fullDate else { return nil }
        return max(fullDate, updatedAt.addingTimeInterval(60))
    }
}
