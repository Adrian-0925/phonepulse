import SwiftUI
import UIKit

/// 真机诊断页：展示各项原始读数和运行事件，可以一键复制成文字报告。
/// 用来确认"编译通过"之外的东西：在真机上数据读不读得到、悬浮窗在后台是否一直在刷新。
struct DiagnosticsView: View {
    @Environment(MetricsEngine.self) private var engine
    @Environment(FloatingSpeedController.self) private var floating
    @State private var copied = false

    private var diagnostics: EngineDiagnostics { engine.diagnostics }
    private var log: EventLog { EventLog.shared }
    private var liveActivity: LiveActivityService { .shared }

    private var updateDurationText: String {
        liveActivity.lastUpdateDuration.map { String(format: "%.2f 秒", $0) } ?? "--"
    }

    var body: some View {
        List {
            Section {
                Button {
                    UIPasteboard.general.string = report
                    copied = true
                } label: {
                    Label(copied ? "已复制，可以直接粘贴发送" : "复制诊断报告", systemImage: copied ? "checkmark.circle" : "doc.on.doc")
                }
            } footer: {
                Text("报告只包含机型、系统版本和各项原始读数，不包含设备名称等个人信息。")
            }

            Section("设备") {
                LabeledContent("机型标识", value: DeviceCatalog.identifier)
                LabeledContent("机型", value: DeviceCatalog.displayName)
                LabeledContent("系统", value: "iOS \(UIDevice.current.systemVersion)")
                LabeledContent("App 版本", value: Self.appVersion)
                LabeledContent("已采样", value: "\(diagnostics.tickCount) 次")
            }

            Section {
                LabeledContent("数据来源", value: cpuSourceText)
                LabeledContent("当前占用", value: engine.snapshot?.cpu.map { Format.percent($0.usage) } ?? "--")
            } header: {
                Text("CPU")
            } footer: {
                Text("显示「仅本 App」说明系统不允许读取整机 CPU 数据。")
            }

            Section {
                LabeledContent("原始电量值", value: rawBatteryText)
                LabeledContent("充电状态", value: engine.snapshot?.battery.state.label ?? "--")
                LabeledContent("最小电量跳变", value: batteryStepText)
                LabeledContent("电量变化点", value: "\(diagnostics.batteryChangePoints) 个")
                LabeledContent("功率估算", value: powerText)
            } header: {
                Text("电池")
            } footer: {
                Text("最小跳变是 1% 表示系统按 1% 报告电量；是 5% 的话功率估算需要更久。充电或放电几分钟后才会有数据。")
            }

            Section {
                LabeledContent("设备支持", value: yesNo(floating.isSupported))
                LabeledContent("当前可开启", value: yesNo(floating.isPossible))
                LabeledContent("已开启", value: yesNo(floating.isActive))
                LabeledContent("音频会话", value: floating.audioSessionReady ? "playback（混音）" : "未配置")
                LabeledContent("后台采样", value: "\(diagnostics.backgroundTickCount) 次")
                LabeledContent("后台最大间隔", value: backgroundGapText)
                LabeledContent("渲染器重置", value: "\(floating.rendererResetCount) 次")
                LabeledContent("离开 App 时显示", value: floating.showsOutsideApp ? "开" : "关")
                Text(backgroundVerdict)
                    .font(.subheadline)
            } header: {
                Text("悬浮窗")
            } footer: {
                Text("开启悬浮窗后切到其他 App 待几分钟再回来看。后台最大间隔接近 1 秒说明后台一直在刷新；锁屏期间出现中断属于正常。")
            }

            Section {
                LabeledContent("运行中", value: yesNo(liveActivity.isRunning))
                LabeledContent("重点显示", value: liveActivity.focus.label)
                LabeledContent("最近 60 秒推送", value: "\(liveActivity.pushesInLastMinute) 次")
                LabeledContent("本次共推送", value: "\(liveActivity.pushCount) 次")
                LabeledContent("最近一次推送", value: liveActivity.lastPushDate.map { $0.formatted(date: .omitted, time: .standard) } ?? "--")
                LabeledContent("系统处理一次更新", value: updateDurationText)
            } header: {
                Text("灵动岛")
            } footer: {
                Text("网速一直在变时，最近 60 秒推送应接近 60 次。系统处理一次更新超过 1 秒，说明延迟发生在系统调度，而不是 App 采集。")
            }

            Section {
                if trafficInterfaces.isEmpty {
                    Text("暂无数据")
                }
                ForEach(trafficInterfaces, id: \.name) { reading in
                    LabeledContent {
                        Text("↓ \(Format.bytes(UInt64(reading.receivedBytes)))  ↑ \(Format.bytes(UInt64(reading.sentBytes)))")
                            .monospacedDigit()
                    } label: {
                        Text("\(reading.name)（\(Self.kindLabel(reading.name))）")
                    }
                }
            } header: {
                Text("网卡原始计数")
            } footer: {
                Text("en0 = Wi-Fi，pdp_ip = 蜂窝，utun = VPN（不计入网速，避免重复）。计数是 32 位的，超过 4 GB 会从 0 重新开始。")
            }

            Section("事件日志") {
                if log.entries.isEmpty {
                    Text("暂无事件")
                }
                ForEach(Array(log.entries.reversed())) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.date, format: .dateTime.hour().minute().second())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(entry.message)
                            .font(.subheadline)
                    }
                }
            }
        }
        .navigationTitle("真机诊断")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - 文字报告

    private var report: String {
        let snapshot = engine.snapshot
        let connection = snapshot?.network.connection.label ?? "--"
        let download = snapshot.map { Format.speed($0.network.downloadBytesPerSecond) } ?? "--"
        let upload = snapshot.map { Format.speed($0.network.uploadBytesPerSecond) } ?? "--"
        let cpuUsage = snapshot?.cpu.map { Format.percent($0.usage) } ?? "--"
        let batteryState = snapshot?.battery.state.label ?? "--"
        let thermal = snapshot?.thermal.label ?? "--"
        let lowPower = yesNo(snapshot?.battery.isLowPowerMode ?? false)
        let audio = floating.audioSessionReady ? "playback" : "未配置"

        var lines: [String] = []
        lines.append("PhonePulse 诊断报告")
        lines.append("生成时间：\(Date.now.formatted(date: .numeric, time: .standard))")
        lines.append("App 版本：\(Self.appVersion)")
        lines.append("机型：\(DeviceCatalog.identifier)（\(DeviceCatalog.displayName)），iOS \(UIDevice.current.systemVersion)")
        lines.append("已采样：\(diagnostics.tickCount) 次")
        lines.append("")
        lines.append("【网络】连接：\(connection)，下载 \(download)，上传 \(upload)")
        lines.append("【CPU】数据来源：\(cpuSourceText)，当前占用：\(cpuUsage)")
        lines.append("【电池】原始值：\(rawBatteryText)，状态：\(batteryState)，最小跳变：\(batteryStepText)，变化点：\(diagnostics.batteryChangePoints) 个，功率估算：\(powerText)")
        lines.append("【温度】\(thermal)，低电量模式：\(lowPower)")
        lines.append("【悬浮窗】支持：\(yesNo(floating.isSupported))，可开启：\(yesNo(floating.isPossible))，已开启：\(yesNo(floating.isActive))，音频会话：\(audio)")
        lines.append("  后台采样：\(diagnostics.backgroundTickCount) 次，后台最大间隔：\(backgroundGapText)，渲染器重置：\(floating.rendererResetCount) 次，离开 App 时显示：\(floating.showsOutsideApp ? "开" : "关")")
        lines.append("【灵动岛】运行中：\(yesNo(liveActivity.isRunning))，重点：\(liveActivity.focus.label)，最近 60 秒推送：\(liveActivity.pushesInLastMinute) 次，共推送：\(liveActivity.pushCount) 次，系统处理一次更新：\(updateDurationText)")
        lines.append("  结论：\(backgroundVerdict)")
        lines.append("【网卡原始计数】")
        for reading in trafficInterfaces {
            lines.append("  \(reading.name)（\(Self.kindLabel(reading.name))）rx=\(reading.receivedBytes) tx=\(reading.sentBytes)")
        }
        lines.append("【事件日志】")
        for entry in log.entries {
            lines.append("  \(entry.date.formatted(date: .omitted, time: .standard)) \(entry.message)")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - 文案

    private var cpuSourceText: String {
        guard let cpu = engine.snapshot?.cpu else { return "采样中" }
        return cpu.isSystemWide ? "整机（\(cpu.coreCount) 核）" : "仅本 App"
    }

    private var rawBatteryText: String {
        diagnostics.rawBatteryLevel < 0 ? "不可用" : String(format: "%.3f", diagnostics.rawBatteryLevel)
    }

    private var batteryStepText: String {
        guard let step = diagnostics.smallestBatteryStep else { return "尚未观察到变化" }
        return String(format: "%.1f%%", step * 100)
    }

    private var powerText: String {
        guard let battery = engine.snapshot?.battery else { return "--" }
        guard let watts = battery.estimatedPowerWatts else { return "数据不足" }
        let capacity = battery.capacityMAh.map { "\($0) mAh" } ?? "未知"
        return "\(Format.watts(watts))（估算，容量 \(capacity)）"
    }

    private var backgroundGapText: String {
        diagnostics.backgroundTickCount > 0 ? String(format: "%.1f 秒", diagnostics.maxBackgroundGap) : "--"
    }

    private var backgroundVerdict: String {
        guard diagnostics.backgroundTickCount > 0 else { return "还没有后台数据：开启悬浮窗后切到其他 App 待一会儿" }
        if diagnostics.maxBackgroundGap <= 2.5 {
            return "✅ 后台一直在刷新"
        }
        return String(format: "⚠️ 后台出现过 %.0f 秒的中断", diagnostics.maxBackgroundGap)
    }

    private var trafficInterfaces: [InterfaceReading] {
        diagnostics.interfaces
            .filter { $0.receivedBytes > 0 || $0.sentBytes > 0 }
            .sorted { $0.name < $1.name }
    }

    private func yesNo(_ value: Bool) -> String {
        value ? "是" : "否"
    }

    private static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "-"
        let build = info?["CFBundleVersion"] as? String ?? "-"
        return "\(version) (\(build))"
    }

    private static func kindLabel(_ name: String) -> String {
        switch InterfaceKind(interfaceName: name) {
        case .wifi: "Wi-Fi"
        case .cellular: "蜂窝"
        case nil: "不计入"
        }
    }
}
