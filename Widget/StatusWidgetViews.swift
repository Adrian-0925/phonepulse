import AppIntents
import SwiftUI
import WidgetKit

struct StatusWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StatusEntry

    var body: some View {
        switch family {
        case .systemSmall: SmallStatusView(entry: entry)
        case .systemMedium: MediumStatusView(entry: entry)
        case .systemLarge: LargeStatusView(entry: entry)
        case .accessoryCircular: CircularStatusView(display: entry.hero)
        case .accessoryRectangular: RectangularStatusView(entry: entry)
        case .accessoryInline: InlineStatusView(entry: entry)
        default: SmallStatusView(entry: entry)
        }
    }
}

// MARK: - 主屏幕：小

/// 一个主指标大字显示，下面两个次要指标，底部是更新时间和刷新按钮
private struct SmallStatusView: View {
    let entry: StatusEntry

    var body: some View {
        let hero = entry.hero
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                MetricTitle(display: hero)
                Spacer(minLength: 4)
                RefreshButton()
            }
            Spacer(minLength: 2)
            ValueText(display: hero, size: 40)
            Text(hero.detail)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
            if let progress = hero.progress {
                BarGauge(progress: progress, tint: hero.tint, height: 5)
                    .padding(.top, 6)
            }
            Spacer(minLength: 4)
            if entry.preset != .minimal {
                HStack(spacing: 10) {
                    ForEach(Array(entry.secondary.prefix(2).enumerated()), id: \.offset) { item in
                        CompactChip(display: item.element)
                    }
                }
                .padding(.bottom, 3)
            }
            UpdatedText(date: entry.date)
        }
    }
}

// MARK: - 主屏幕：中

/// 左边主指标（环形进度），右边 2×2 次要指标
private struct MediumStatusView: View {
    let entry: StatusEntry

    var body: some View {
        let hero = entry.hero
        let tiles = Array(entry.secondary.prefix(entry.preset == .minimal ? 2 : 4))
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                MetricTitle(display: hero)
                HeroGauge(display: hero, diameter: 70)
                Text(hero.detail)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    UpdatedText(date: entry.date)
                    RefreshButton()
                }
            }
            .frame(width: 118, alignment: .leading)
            TileGrid(displays: tiles, columns: 2)
                .frame(maxHeight: .infinity, alignment: .center)
        }
    }
}

// MARK: - 主屏幕：大

/// 主指标 + 24 小时电量曲线 + 六个次要指标 + 灵动岛开关
private struct LargeStatusView: View {
    let entry: StatusEntry

    var body: some View {
        let hero = entry.hero
        let tiles = Array(entry.secondary.prefix(entry.preset == .minimal ? 3 : 6))
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text("PhonePulse")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Text(DeviceCatalog.displayName)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                UpdatedText(date: entry.date)
                RefreshButton()
            }
            HStack(spacing: 14) {
                HeroGauge(display: hero, diameter: 80)
                VStack(alignment: .leading, spacing: 4) {
                    MetricTitle(display: hero)
                    Text(hero.detail)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary.opacity(0.9))
                        .lineLimit(2)
                    SourceTag(source: hero.source)
                }
                Spacer(minLength: 0)
                LiveActivityButton()
            }
            BatteryCurveView(history: entry.history, now: entry.date)
                .frame(height: 62)
            TileGrid(displays: tiles, columns: 3)
        }
    }
}

// MARK: - 锁屏

private struct CircularStatusView: View {
    let display: MetricDisplay

    var body: some View {
        if let progress = display.progress {
            Gauge(value: progress) {
                Image(systemName: display.icon)
            } currentValueLabel: {
                Text(display.value)
                    .font(Theme.number(14))
                    .minimumScaleFactor(0.5)
            }
            .gaugeStyle(.accessoryCircular)
            .widgetAccentable()
        } else {
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: display.icon)
                        .font(.system(size: 11, weight: .bold))
                    Text(display.value)
                        .font(Theme.number(13))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                }
                .padding(4)
            }
        }
    }
}

private struct RectangularStatusView: View {
    let entry: StatusEntry

    var body: some View {
        let hero = entry.hero
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Image(systemName: hero.icon)
                Text(hero.title)
            }
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(hero.value)
                    .font(Theme.number(22))
                    .widgetAccentable()
                Text(hero.unit)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            }
            if let second = entry.secondary.first {
                Text("\(second.title) \(second.value)\(second.unit)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct InlineStatusView: View {
    let entry: StatusEntry

    var body: some View {
        let hero = entry.hero
        if let second = entry.secondary.first {
            Text("\(hero.title) \(hero.value)\(hero.unit) · \(second.value)\(second.unit)")
        } else {
            Text("\(hero.title) \(hero.value)\(hero.unit)")
        }
    }
}

// MARK: - 共用部件

private struct MetricTitle: View {
    let display: MetricDisplay

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: display.icon)
            Text(display.title)
                .lineLimit(1)
        }
        .font(.system(size: 12, weight: .semibold, design: .rounded))
        .foregroundStyle(display.tint)
    }
}

/// 大号数字 + 小号单位；估算值前面加「≈」
private struct ValueText: View {
    let display: MetricDisplay
    let size: CGFloat

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            if display.source == .estimated && !display.unit.isEmpty {
                Text("≈")
                    .font(Theme.number(size * 0.5, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            Text(display.value)
                .font(Theme.number(size))
                .foregroundStyle(Theme.textPrimary)
                .widgetAccentable()
            if !display.unit.isEmpty {
                Text(display.unit)
                    .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.5)
    }
}

/// 有进度概念的指标画成环形，没有的（网速）直接大字显示
private struct HeroGauge: View {
    let display: MetricDisplay
    let diameter: CGFloat

    var body: some View {
        if let progress = display.progress {
            RingGauge(progress: progress, tint: display.tint, lineWidth: diameter * 0.1) {
                VStack(spacing: 0) {
                    Text(display.value)
                        .font(Theme.number(diameter * 0.3))
                        .foregroundStyle(Theme.textPrimary)
                        .widgetAccentable()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    if !display.unit.isEmpty {
                        Text(display.unit)
                            .font(.system(size: diameter * 0.13, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .padding(diameter * 0.14)
            }
            .frame(width: diameter, height: diameter)
        } else {
            ValueText(display: display, size: diameter * 0.4)
                .frame(height: diameter, alignment: .leading)
        }
    }
}

private struct MiniTile: View {
    let display: MetricDisplay

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 3) {
                Image(systemName: display.icon)
                Text(display.title)
                    .lineLimit(1)
            }
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(display.tint)
            ValueText(display: display, size: 18)
            if let progress = display.progress {
                BarGauge(progress: progress, tint: display.tint, height: 3)
            } else {
                Text(display.detail)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TileGrid: View {
    let displays: [MetricDisplay]
    let columns: Int

    var body: some View {
        let rows = (displays.count + columns - 1) / columns
        VStack(spacing: 10) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(alignment: .top, spacing: 10) {
                    ForEach(0..<columns, id: \.self) { column in
                        let index = row * columns + column
                        if index < displays.count {
                            MiniTile(display: displays[index])
                        } else {
                            Color.clear
                                .frame(maxWidth: .infinity, maxHeight: 1)
                        }
                    }
                }
            }
        }
    }
}

private struct CompactChip: View {
    let display: MetricDisplay

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: display.icon)
                .foregroundStyle(display.tint)
            Text(display.value + display.unit)
                .foregroundStyle(Theme.textPrimary)
        }
        .font(.system(size: 11, weight: .semibold, design: .rounded))
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}

private struct SourceTag: View {
    let source: DataSource

    var body: some View {
        Text(source.label)
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Theme.track, in: Capsule())
    }
}

private struct UpdatedText: View {
    let date: Date

    var body: some View {
        Text("\(Text(date, style: .time)) 更新")
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .foregroundStyle(Theme.textSecondary)
            .lineLimit(1)
    }
}

/// 点一下立即刷新，不用打开 App
private struct RefreshButton: View {
    var body: some View {
        Button(intent: RefreshStatusIntent()) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.textPrimary.opacity(0.85))
                .frame(width: 22, height: 22)
                .background(Theme.track, in: Circle())
        }
        .buttonStyle(.plain)
    }
}

/// 点一下开关灵动岛，不用打开 App
private struct LiveActivityButton: View {
    var body: some View {
        Button(intent: ToggleLiveActivityIntent()) {
            VStack(spacing: 3) {
                Image(systemName: "capsule.fill")
                    .font(.system(size: 14, weight: .bold))
                Text("灵动岛")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(Theme.charging)
            .frame(width: 54, height: 48)
            .background(Theme.charging.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// 24 小时电量曲线，插电的时段用黄色标出
private struct BatteryCurveView: View {
    let history: [BatteryPoint]
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("24 小时电量")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text("小组件每次刷新记一个点")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textSecondary.opacity(0.8))
            }
            if history.count >= 2 {
                GeometryReader { geometry in
                    ZStack {
                        Path { path in
                            path.move(to: CGPoint(x: 0, y: geometry.size.height / 2))
                            path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height / 2))
                        }
                        .stroke(Theme.track, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        Self.areaPath(history, now: now, size: geometry.size)
                            .fill(LinearGradient(colors: [Theme.battery.opacity(0.35), Theme.battery.opacity(0)], startPoint: .top, endPoint: .bottom))
                        Self.linePath(history, now: now, size: geometry.size)
                            .stroke(Theme.battery, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        Self.chargingPath(history, now: now, size: geometry.size)
                            .stroke(Theme.charging, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    }
                }
            } else {
                Text("小组件刷新几次后会显示电量曲线")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private static func position(_ point: BatteryPoint, now: Date, size: CGSize) -> CGPoint {
        let start = now.addingTimeInterval(-BatteryHistory.retention)
        let x = CGFloat(point.time.timeIntervalSince(start) / BatteryHistory.retention) * size.width
        let y = (1 - CGFloat(point.level)) * size.height
        return CGPoint(x: min(max(x, 0), size.width), y: y)
    }

    private static func linePath(_ points: [BatteryPoint], now: Date, size: CGSize) -> Path {
        var path = Path()
        for (index, point) in points.enumerated() {
            let location = position(point, now: now, size: size)
            if index == 0 {
                path.move(to: location)
            } else {
                path.addLine(to: location)
            }
        }
        return path
    }

    private static func areaPath(_ points: [BatteryPoint], now: Date, size: CGSize) -> Path {
        var path = linePath(points, now: now, size: size)
        guard let first = points.first, let last = points.last else { return path }
        path.addLine(to: CGPoint(x: position(last, now: now, size: size).x, y: size.height))
        path.addLine(to: CGPoint(x: position(first, now: now, size: size).x, y: size.height))
        path.closeSubpath()
        return path
    }

    /// 相邻两个点都插着电的线段
    private static func chargingPath(_ points: [BatteryPoint], now: Date, size: CGSize) -> Path {
        var path = Path()
        for index in points.indices.dropFirst() where points[index].isCharging && points[index - 1].isCharging {
            path.move(to: position(points[index - 1], now: now, size: size))
            path.addLine(to: position(points[index], now: now, size: size))
        }
        return path
    }
}
