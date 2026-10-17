import SwiftUI
import WidgetKit

/// 电池详情：区分几种"容量"，每个数值都标明是实测、估算、规格还是手动填写。
struct BatteryDetailView: View {
    @Environment(MetricsEngine.self) private var engine
    @AppStorage(SharedStore.Key.batteryHealthPercent, store: SharedStore.defaults) private var healthPercent = 0
    @AppStorage(SharedStore.Key.batteryCycleCount, store: SharedStore.defaults) private var cycleCount = 0
    @AppStorage(SharedStore.Key.batteryCapacityOverride, store: SharedStore.defaults) private var designOverride = 0

    private var battery: BatterySample? { engine.snapshot?.battery }
    private var settings: BatterySettings {
        BatterySettings(designOverride: designOverride, healthPercent: healthPercent, cycleCount: cycleCount)
    }

    var body: some View {
        Form {
            Section {
                SourceRow(title: "剩余电量", value: battery?.level.map(Format.percent) ?? "--", source: .measured)
                SourceRow(title: "状态", value: battery?.state.label ?? "--", source: .measured)
                SourceRow(title: "低电量模式", value: battery?.isLowPowerMode == true ? "开启" : "关闭", source: .measured)
            } header: {
                Text("当前状态")
            }

            Section {
                SourceRow(title: speedTitle, value: battery?.levelPerHour.map(Format.levelRate) ?? "估算中", source: .estimated)
                SourceRow(title: "电池功率", value: powerText, source: .estimated)
                if let eta = timeToFullText {
                    SourceRow(title: "预计充满", value: eta, source: .estimated)
                }
            } header: {
                Text("充电 / 耗电")
            } footer: {
                Text("iOS 不开放充电电压和电流，这里根据电量变化速度推算，需要 App 保持打开几分钟。功率指电池实际充入（或消耗）的功率，比充电头标称功率低是正常的；电量到 80% 左右时系统可能放慢充电。")
            }

            Section {
                SourceRow(title: "设计容量", value: settings.designMAh.map { "\($0) mAh" } ?? "未收录", source: designOverride > 0 ? .manual : .spec)
                SourceRow(title: "最大容量", value: healthPercent > 0 ? "\(healthPercent)%" : "未填写", source: .manual)
                SourceRow(title: "当前满电容量", value: capacityText(\.fullChargeMAh), source: .computed)
                SourceRow(title: "剩余电量（mAh）", value: remainingText, source: .estimated)
                SourceRow(title: "循环次数", value: cycleCount > 0 ? "\(cycleCount) 次" : "未填写", source: .manual)
            } header: {
                Text("容量与健康")
            } footer: {
                Text("设计容量是出厂标称值；最大容量是电池老化后还剩的比例；两者相乘就是现在充满时实际能存的电量。iOS 不允许 App 读取电池健康和循环次数，需要你从系统设置里看到后填在下面。")
            }

            Section {
                NumberField(title: "最大容量（%）", value: $healthPercent, range: 0...100)
                NumberField(title: "循环次数", value: $cycleCount, range: 0...5000)
                if DeviceCatalog.current == nil || designOverride > 0 {
                    NumberField(title: "设计容量（mAh）", value: $designOverride, range: 0...10000)
                }
            } header: {
                Text("手动填写")
            } footer: {
                Text("最大容量：设置 → 电池 → 电池健康与充电。\n循环次数：iPhone 15 及以后机型在 设置 → 通用 → 关于本机。\n填 0 表示不使用。")
            }
        }
        .navigationTitle("电池")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: healthPercent) { WidgetCenter.shared.reloadAllTimelines() }
        .onChange(of: designOverride) { WidgetCenter.shared.reloadAllTimelines() }
    }

    private var speedTitle: String {
        guard let rate = battery?.levelPerHour else { return "电量变化速度" }
        return rate >= 0 ? "充电速度" : "耗电速度"
    }

    private var powerText: String {
        guard let watts = battery?.estimatedPowerWatts else { return "估算中" }
        return "≈ \(Format.watts(abs(watts)))（\(watts >= 0 ? "充入" : "消耗")）"
    }

    private var timeToFullText: String? {
        guard let battery, battery.state == .charging, let level = battery.level, let rate = battery.levelPerHour,
              let seconds = ChargeForecast.timeToFull(level: level, levelPerHour: rate) else { return nil }
        return "约 \(Format.duration(seconds))"
    }

    private var remainingText: String {
        guard let capacity = settings.capacity, let level = battery?.level else { return "--" }
        return "≈ \(capacity.remainingMAh(level: level)) mAh"
    }

    private func capacityText(_ keyPath: KeyPath<BatteryCapacity, Int>) -> String {
        guard let capacity = settings.capacity else { return "--" }
        let value = capacity[keyPath: keyPath]
        return healthPercent > 0 ? "\(value) mAh" : "\(value) mAh（按 100% 计）"
    }
}

/// 一行数据 + 来源标签
private struct SourceRow: View {
    let title: String
    let value: String
    let source: DataSource

    var body: some View {
        LabeledContent {
            HStack(spacing: 6) {
                Text(value)
                    .monospacedDigit()
                Text(source.label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.quaternary, in: Capsule())
            }
        } label: {
            Text(title)
        }
    }
}

private struct NumberField: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        LabeledContent(title) {
            TextField("0", value: Binding(get: { value }, set: { value = min(max($0, range.lowerBound), range.upperBound) }), format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
        }
    }
}
