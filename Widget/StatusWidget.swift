import AppIntents
import SwiftUI
import WidgetKit

/// 小组件配置：长按小组件 →「编辑小组件」时看到的选项
struct StatusWidgetIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "PhonePulse"
    static var description = IntentDescription("选择小组件上显示的内容。")

    @Parameter(title: "展示预设", default: .overview)
    var preset: WidgetPreset

    @Parameter(title: "自定义指标", description: "预设选「自定义」时生效，第一个会大字显示")
    var customMetrics: [MetricKind]?

    var metrics: [MetricKind] {
        if preset == .custom, let customMetrics, !customMetrics.isEmpty {
            return customMetrics
        }
        return preset.metrics
    }
}

struct StatusEntry: TimelineEntry {
    let date: Date
    let snapshot: MetricsSnapshot
    let history: [BatteryPoint]
    let metrics: [MetricKind]
    let preset: WidgetPreset

    var displays: [MetricDisplay] { metrics.map { $0.display(for: snapshot) } }
    var hero: MetricDisplay { displays.first ?? MetricKind.battery.display(for: snapshot) }
    var secondary: [MetricDisplay] { Array(displays.dropFirst()) }

    static func preview(preset: WidgetPreset = .overview, metrics: [MetricKind]? = nil) -> StatusEntry {
        let now = Date.now
        // 预览用的假电量曲线：从昨晚 92% 一路掉到 41%，下午充了一会儿电
        let history = (0..<48).map { index -> BatteryPoint in
            let hoursAgo = Double(47 - index) / 2
            let charging = hoursAgo < 3 && hoursAgo > 1
            let level = charging ? 0.41 + (3 - hoursAgo) * 0.12 : max(0.92 - (24 - hoursAgo) * 0.022, 0.2)
            return BatteryPoint(time: now.addingTimeInterval(-hoursAgo * 3600), level: min(level, 1), isCharging: charging)
        }
        return StatusEntry(date: now, snapshot: .placeholder, history: history, metrics: metrics ?? preset.metrics, preset: preset)
    }
}

struct StatusProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> StatusEntry {
        .preview()
    }

    func snapshot(for configuration: StatusWidgetIntent, in context: Context) async -> StatusEntry {
        if context.isPreview {
            return .preview(preset: configuration.preset, metrics: configuration.metrics)
        }
        return await makeEntry(configuration)
    }

    func timeline(for configuration: StatusWidgetIntent, in context: Context) async -> Timeline<StatusEntry> {
        let entry = await makeEntry(configuration)
        // 这里只是"希望"的刷新时间，实际由系统按刷新额度决定（通常 15 分钟以上一次）
        let minutes: Double = entry.snapshot.battery.state == .charging ? 5 : 15
        return Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(minutes * 60)))
    }

    private func makeEntry(_ configuration: StatusWidgetIntent) async -> StatusEntry {
        let sample = await WidgetSampler.sample()
        return StatusEntry(
            date: .now,
            snapshot: sample.snapshot,
            history: sample.history,
            metrics: configuration.metrics,
            preset: configuration.preset)
    }
}

struct StatusWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "PhonePulseStatus", intent: StatusWidgetIntent.self, provider: StatusProvider()) { entry in
            StatusWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    WidgetBackground()
                }
        }
        .configurationDisplayName("手机状态")
        .description("电量、充电、网速、CPU、存储一眼看清。长按小组件可以换展示内容。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

private struct WidgetBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Theme.background(colorScheme)
    }
}

@main
struct PhonePulseWidgetBundle: WidgetBundle {
    var body: some Widget {
        StatusWidget()
        StatusLiveActivity()
    }
}

#Preview("小", as: .systemSmall) {
    StatusWidget()
} timeline: {
    StatusEntry.preview()
}

#Preview("中", as: .systemMedium) {
    StatusWidget()
} timeline: {
    StatusEntry.preview()
}

#Preview("大", as: .systemLarge) {
    StatusWidget()
} timeline: {
    StatusEntry.preview()
}
