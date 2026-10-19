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
                SourceRow(title: "剩余电量", value: battery?.level.map(Format.batteryPercent) ?? "--", source: .measured)
                SourceRow(title: "状态", value: battery?.state.label ?? "--", source: .measured)
                SourceRow(title: "低电量模式", value: battery?.isLowPowerMode == true ? "开启" : "关闭", source: .measured)
                SourceRow(title: "系统电量精度", value: precisionText, source: .measured)
            } header: {
                Text("当前状态")
            } footer: {
                Text("iOS 给 App 的电量可能是按 5% 一档取整的，这时会和状态栏的电量差几个百分点，这是系统的限制。电量变化一次后这里会显示实际精度。")
            }

            Section {
                if let battery {
                    let readout = PowerReadout(battery: battery, now: .now)
                    LabeledContent("测定状态") {
                        PowerStatusBadge(readout: readout)
                    }
                    SourceRow(title: speedTitle, value: readout.hasResult ? (battery.levelPerHour.map(Format.levelRate) ?? "--") : "--", source: .estimated)
                    SourceRow(title: readout.title, value: readout.value, source: .estimated)
                    if let eta = timeToFullText {
                        SourceRow(title: "预计充满", value: eta, source: .estimated)
                    }
                    Text(readout.detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    DisclosureGroup("怎么测的、准不准") {
                        Text(methodText(battery))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("正在读取电池数据…")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("充电 / 耗电")
            } footer: {
                Text("功率是根据电量变化推算的电池实际充入（或消耗）功率，比充电头标称功率低是正常的。插拔充电器后会重新测定。")
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

    /// 本次运行观察到的最小电量跳变：1% 说明和系统一致，5% 说明系统只给 App 取整后的电量
    private var precisionText: String {
        guard let step = engine.diagnostics.smallestBatteryStep else { return "观察中（电量变化一次后显示）" }
        if step >= 0.045 { return "5% 一档" }
        if step <= 0.015 { return "1% 一档" }
        return String(format: "%.0f%% 一档", step * 100)
    }

    private var speedTitle: String {
        guard let rate = battery?.levelPerHour else { return "电量变化速度" }
        return rate >= 0 ? "充电速度" : "耗电速度"
    }

    /// 专业解释：数据来源、计算方法、误差来源，以及本次实际看到的电量精度和变化间隔
    private func methodText(_ battery: BatterySample) -> String {
        var lines: [String] = []
        lines.append("来源：iOS 只给 App 电量百分比和是否在充电（实测），不开放电压、电流，所以功率是估算值。")
        lines.append("计算：只用「电量刚变化的那一刻」。两次变化之间正好涨（或掉）一档，用这一档除以用时得到速度；功率 = 速度 × 满电容量 × 3.85V。")
        lines.append("阶段：至少看到 2 次电量变化、跨度 ≥ 36 秒给出「初步估算」；至少 3 次变化、跨度 ≥ 2.5 分钟算「较稳定」。电量比平时久得多没变（比如优化充电），改为「已放缓」并只给上限。")
        if let status = battery.power, let error = status.timingError {
            lines.append(String(format: "本轮计时误差约 ±%.0f%%（采样间隔 ÷ 跨度）。", error * 100))
        }
        lines.append("精度：系统电量 \(precisionText)。1% 一档、约 20W 快充时 1 分钟左右出初步结果；5% 一档或慢充时要几分钟，这是系统数据精度决定的，无法再缩短。")
        let intervals = engine.diagnostics.batteryChangeIntervals
        if !intervals.isEmpty {
            lines.append("最近几次电量变化间隔：" + intervals.map { String(format: "%.0f 秒", $0) }.joined(separator: "、"))
        }
        lines.append("其他误差：电池实际电压在 3.7–4.4V 之间变化、满电容量取决于你填写的最大容量，所以功率本身约有 ±10% 的误差，显示时只保留两位有效数字。")
        return lines.joined(separator: "\n\n")
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
