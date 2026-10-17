import SwiftUI
import WidgetKit

/// 小组件不能实时刷新（系统控制频率，约 15 分钟以上一次），
/// 所以显示的是主 App 最近一次保存的快照，并标出更新时间。
struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: MetricsSnapshot?
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        let snapshot = context.isPreview ? nil : SharedStore.load()
        completion(SnapshotEntry(date: .now, snapshot: snapshot ?? .placeholder))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let entry = SnapshotEntry(date: .now, snapshot: SharedStore.load())
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(15 * 60))))
    }
}

struct StatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "StatusWidget", provider: SnapshotProvider()) { entry in
            StatusWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("设备状态")
        .description("电量、存储、内存一览。数据来自上次打开 App 时。")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

@main
struct PhonePulseWidgetBundle: WidgetBundle {
    var body: some Widget {
        StatusWidget()
    }
}

// MARK: - 视图

struct StatusWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    var body: some View {
        if let snapshot = entry.snapshot {
            switch family {
            case .accessoryRectangular:
                RectangularView(snapshot: snapshot)
            case .systemMedium:
                MediumView(snapshot: snapshot)
            default:
                SmallView(snapshot: snapshot)
            }
        } else {
            Text("打开 App 一次以获取数据")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct SmallView: View {
    let snapshot: MetricsSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            BatteryHeadline(battery: snapshot.battery)
            Spacer(minLength: 0)
            WidgetRow(title: "存储", value: snapshot.storage.map { "剩 \(Format.bytes($0.availableBytes))" } ?? "--")
            WidgetRow(title: "内存", value: snapshot.memory.map { Format.percent($0.usedFraction) } ?? "--")
            UpdatedLabel(date: snapshot.timestamp)
        }
    }
}

private struct MediumView: View {
    let snapshot: MetricsSnapshot

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading) {
                BatteryHeadline(battery: snapshot.battery)
                Spacer(minLength: 0)
                UpdatedLabel(date: snapshot.timestamp)
            }
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                WidgetRow(title: "存储", value: snapshot.storage.map { "剩 \(Format.bytes($0.availableBytes))" } ?? "--")
                WidgetRow(title: "内存", value: snapshot.memory.map { Format.percent($0.usedFraction) } ?? "--")
                WidgetRow(title: "CPU", value: snapshot.cpu.map { Format.percent($0.usage) } ?? "--")
                WidgetRow(title: "温度", value: snapshot.thermal.label)
            }
        }
    }
}

private struct RectangularView: View {
    let snapshot: MetricsSnapshot

    var body: some View {
        VStack(alignment: .leading) {
            Text("电量 \(snapshot.battery.level.map(Format.percent) ?? "--") · \(snapshot.battery.state.label)")
                .font(.headline)
            if let storage = snapshot.storage {
                Text("存储剩余 \(Format.bytes(storage.availableBytes))")
            }
        }
    }
}

private struct BatteryHeadline: View {
    let battery: BatterySample

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(battery.state.label, systemImage: battery.state == .charging ? "bolt.fill" : "battery.75percent")
                .font(.caption)
                .foregroundStyle(battery.state == .charging ? Color.green : Color.secondary)
            Text(battery.level.map(Format.percent) ?? "--")
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
    }
}

private struct WidgetRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .monospacedDigit()
        }
        .font(.caption)
    }
}

private struct UpdatedLabel: View {
    let date: Date

    var body: some View {
        Text("\(Text(date, style: .relative))前更新")
            .font(.caption2)
            .foregroundStyle(.tertiary)
    }
}

#Preview(as: .systemSmall) {
    StatusWidget()
} timeline: {
    SnapshotEntry(date: .now, snapshot: .placeholder)
}
