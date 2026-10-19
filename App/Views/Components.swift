import Charts
import SwiftUI

/// 仪表盘上的通用卡片
struct MetricCard<Content: View>: View {
    let title: String
    let systemImage: String
    let tint: Color
    let content: Content

    init(title: String, systemImage: String, tint: Color = .accentColor, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(tint)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// 卡片里的大号数值
struct MetricValue: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.title2.monospacedDigit().weight(.semibold))
            .contentTransition(.numericText())
    }
}

/// 功率测定状态的小标签：正在采集（灰）、初步估算（黄）、较稳定（绿）、已放缓 / 已断开（橙）
struct PowerStatusBadge: View {
    let readout: PowerReadout

    var body: some View {
        Text(readout.label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
    }

    private var color: Color {
        switch readout.status {
        case .stable, .full: Theme.battery
        case .preliminary: Theme.charging
        case .slowed, .disconnected: Theme.storage
        case .collecting, .noData: .gray
        }
    }
}

struct SparklineSeries: Identifiable {
    let id: String
    let values: [Double]
    let color: Color
}

/// 迷你折线图。数据靠右对齐，新数据从右边进入。
struct Sparkline: View {
    let series: [SparklineSeries]
    var capacity: Int = 60
    /// 固定 Y 轴上限（比如 CPU 用 1）；nil 表示按数据自动缩放
    var yMax: Double?

    var body: some View {
        Chart {
            ForEach(series) { line in
                ForEach(Array(line.values.enumerated()), id: \.offset) { item in
                    LineMark(
                        x: .value("时间", capacity - line.values.count + item.offset),
                        y: .value("数值", item.element),
                        series: .value("系列", line.id))
                    .foregroundStyle(line.color)
                    .interpolationMethod(.monotone)
                }
            }
        }
        .chartXScale(domain: 0...max(capacity - 1, 1))
        .chartYScale(domain: 0...(yMax ?? autoMax))
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
    }

    private var autoMax: Double {
        max(series.flatMap(\.values).max() ?? 0, 1) * 1.1
    }
}
