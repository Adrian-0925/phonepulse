import SwiftUI

struct DashboardView: View {
    @Environment(MetricsEngine.self) private var engine

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                if let snapshot = engine.snapshot {
                    VStack(spacing: 12) {
                        NetworkCard(
                            sample: snapshot.network,
                            download: engine.downloadHistory,
                            upload: engine.uploadHistory,
                            capacity: engine.historyLength)
                        LazyVGrid(columns: columns, spacing: 12) {
                            CPUCard(sample: snapshot.cpu, history: engine.cpuHistory, capacity: engine.historyLength)
                            MemoryCard(sample: snapshot.memory)
                            BatteryCard(sample: snapshot.battery)
                            StorageCard(sample: snapshot.storage)
                        }
                        DeviceCard(snapshot: snapshot)
                    }
                    .padding()
                } else {
                    ProgressView()
                        .padding(.top, 120)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("设备状态")
        }
    }
}

// MARK: - 网络

private struct NetworkCard: View {
    let sample: NetworkSample
    let download: [Double]
    let upload: [Double]
    let capacity: Int

    var body: some View {
        MetricCard(title: "网络 · \(sample.connection.label)", systemImage: "arrow.up.arrow.down", tint: .blue) {
            HStack(spacing: 32) {
                speed("下载", value: sample.downloadBytesPerSecond, color: .blue, systemImage: "arrow.down")
                speed("上传", value: sample.uploadBytesPerSecond, color: .orange, systemImage: "arrow.up")
            }
            Sparkline(series: [
                SparklineSeries(id: "download", values: download, color: .blue),
                SparklineSeries(id: "upload", values: upload, color: .orange),
            ], capacity: capacity)
            .frame(height: 60)
            Text("本次统计  Wi-Fi \(Format.bytes(sample.sessionWifiBytes))  ·  蜂窝 \(Format.bytes(sample.sessionCellularBytes))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func speed(_ title: String, value: Double, color: Color, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(color)
            MetricValue(text: Format.speed(value))
        }
    }
}

// MARK: - CPU / 内存 / 电池 / 存储

private struct CPUCard: View {
    let sample: CPUSample?
    let history: [Double]
    let capacity: Int

    var body: some View {
        MetricCard(title: "CPU", systemImage: "cpu", tint: .purple) {
            MetricValue(text: sample.map { Format.percent($0.usage) } ?? "--")
            Sparkline(series: [SparklineSeries(id: "cpu", values: history, color: .purple)], capacity: capacity, yMax: 1)
                .frame(height: 32)
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var caption: String {
        guard let sample else { return "采样中…" }
        return sample.isSystemWide ? "\(sample.coreCount) 核 · 整机" : "仅本 App"
    }
}

private struct MemoryCard: View {
    let sample: MemorySample?

    var body: some View {
        MetricCard(title: "内存", systemImage: "memorychip", tint: .green) {
            if let sample {
                MetricValue(text: Format.percent(sample.usedFraction))
                ProgressView(value: sample.usedFraction)
                    .tint(.green)
                Text("\(Format.bytes(sample.usedBytes)) / \(Format.bytes(sample.totalBytes))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                MetricValue(text: "--")
            }
        }
    }
}

private struct BatteryCard: View {
    let sample: BatterySample

    var body: some View {
        MetricCard(title: "电池", systemImage: icon, tint: sample.state == .charging ? .green : .yellow) {
            MetricValue(text: sample.level.map(Format.percent) ?? "--")
            Text(sample.isLowPowerMode ? "\(sample.state.label) · 低电量模式" : sample.state.label)
                .font(.subheadline)
            Text(powerText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var icon: String {
        sample.state == .charging ? "battery.100percent.bolt" : "battery.75percent"
    }

    private var powerText: String {
        switch (sample.state, sample.estimatedPowerWatts) {
        case (.charging, let watts?) where watts > 0:
            "充入 ≈ \(Format.watts(watts))（估算）"
        case (.unplugged, let watts?) where watts < 0:
            "耗电 ≈ \(Format.watts(-watts))（估算）"
        case (.charging, _), (.unplugged, _):
            sample.capacityMAh == nil ? "未收录此机型容量，可在设置中填写" : "功率估算中，需要几分钟…"
        case (.full, _):
            "已充满"
        case (.unknown, _):
            "当前设备不支持"
        }
    }
}

private struct StorageCard: View {
    let sample: StorageSample?

    var body: some View {
        MetricCard(title: "存储", systemImage: "internaldrive", tint: .teal) {
            if let sample {
                MetricValue(text: Format.bytes(sample.availableBytes))
                ProgressView(value: sample.usedFraction)
                    .tint(.teal)
                Text("可用 / 共 \(Format.bytes(sample.totalBytes))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                MetricValue(text: "--")
            }
        }
    }
}

// MARK: - 设备

private struct DeviceCard: View {
    let snapshot: MetricsSnapshot

    var body: some View {
        MetricCard(title: "设备", systemImage: "iphone", tint: .gray) {
            LabeledContent("机型", value: DeviceCatalog.displayName)
            LabeledContent("系统", value: "iOS \(UIDevice.current.systemVersion)")
            LabeledContent("温度状态", value: snapshot.thermal.label)
            if let footprint = snapshot.memory?.appFootprintBytes {
                LabeledContent("本 App 内存", value: Format.bytes(footprint))
            }
        }
        .font(.subheadline)
    }
}
