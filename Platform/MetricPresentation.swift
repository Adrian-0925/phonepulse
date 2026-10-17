import AppIntents
import SwiftUI

/// 小组件上可以选的指标
enum MetricKind: String, AppEnum, CaseIterable {
    case battery, charging, cpu, memory, storage, network, thermal

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "指标"
    static var caseDisplayRepresentations: [MetricKind: DisplayRepresentation] = [
        .battery: "电量",
        .charging: "充电 / 耗电速度",
        .cpu: "CPU",
        .memory: "内存",
        .storage: "存储",
        .network: "网速",
        .thermal: "发热与温控",
    ]
}

/// 桌面展示预设：选一个就能用，不用逐项设置
enum WidgetPreset: String, AppEnum, CaseIterable {
    case overview, minimal, battery, charging, performance, network, custom

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "展示预设"
    static var caseDisplayRepresentations: [WidgetPreset: DisplayRepresentation] = [
        .overview: "概览（推荐）",
        .minimal: "极简",
        .battery: "电池",
        .charging: "充电",
        .performance: "性能",
        .network: "网络",
        .custom: "自定义",
    ]

    /// 第一个是主指标（大字显示），后面按顺序填进其余位置
    var metrics: [MetricKind] {
        switch self {
        case .overview: [.battery, .network, .cpu, .storage, .memory, .thermal, .charging]
        case .minimal: [.battery, .storage, .memory]
        case .battery: [.battery, .charging, .thermal, .storage, .memory, .cpu]
        case .charging: [.charging, .battery, .thermal, .cpu, .memory, .storage]
        case .performance: [.cpu, .memory, .thermal, .storage, .battery, .network]
        case .network: [.network, .battery, .cpu, .memory, .storage, .thermal]
        case .custom: WidgetPreset.overview.metrics
        }
    }
}

/// 数据来源：界面上要让用户分清哪些是真实读数、哪些是估算
enum DataSource {
    /// 实时读取的整机数据
    case measured
    /// 根据实测数据推算
    case estimated
    /// 机型静态规格
    case spec
    /// 用户手动填写
    case manual
    /// 由其他数值计算得出
    case computed

    var label: String {
        switch self {
        case .measured: "实测"
        case .estimated: "估算"
        case .spec: "规格"
        case .manual: "手动"
        case .computed: "计算"
        }
    }
}

/// 一个指标在界面上的样子
struct MetricDisplay {
    var kind: MetricKind
    var title: String
    var value: String
    var unit: String
    var detail: String
    /// 0...1，nil 表示这个指标没有进度概念（如网速）
    var progress: Double?
    var icon: String
    var tint: Color
    var source: DataSource
}

extension MetricKind {
    func display(for snapshot: MetricsSnapshot) -> MetricDisplay {
        switch self {
        case .battery: batteryDisplay(snapshot.battery)
        case .charging: chargingDisplay(snapshot.battery)
        case .cpu: cpuDisplay(snapshot.cpu)
        case .memory: memoryDisplay(snapshot.memory)
        case .storage: storageDisplay(snapshot.storage)
        case .network: networkDisplay(snapshot.network)
        case .thermal: thermalDisplay(snapshot.thermal, lowPower: snapshot.battery.isLowPowerMode)
        }
    }

    private func batteryDisplay(_ battery: BatterySample) -> MetricDisplay {
        var detail = battery.state.label
        if battery.isLowPowerMode {
            detail += " · 低电量模式"
        }
        let icon: String
        switch battery.state {
        case .charging: icon = "battery.100percent.bolt"
        case .full: icon = "battery.100percent"
        default: icon = (battery.level ?? 1) <= 0.2 ? "battery.25percent" : "battery.75percent"
        }
        return MetricDisplay(
            kind: self,
            title: "电量",
            value: battery.level.map { String(format: "%.0f", $0 * 100) } ?? "--",
            unit: battery.level == nil ? "" : "%",
            detail: detail,
            progress: battery.level,
            icon: icon,
            tint: Theme.batteryColor(level: battery.level, state: battery.state),
            source: .measured)
    }

    private func chargingDisplay(_ battery: BatterySample) -> MetricDisplay {
        var display = MetricDisplay(kind: self, title: "充电", value: "--", unit: "", detail: "", progress: nil, icon: "bolt.fill", tint: Theme.charging, source: .estimated)
        if battery.state == .full {
            display.value = "已满"
            display.detail = "保持插电"
            display.source = .measured
        } else if battery.state == .charging, let watts = battery.estimatedPowerWatts, watts > 0 {
            display.value = String(format: "%.1f", watts)
            display.unit = "W"
            display.detail = chargingDetail(battery)
        } else if let rate = battery.levelPerHour {
            display.title = rate >= 0 ? "充电速度" : "耗电速度"
            display.value = String(format: "%+.0f", rate * 100)
            display.unit = "%/h"
            display.detail = battery.state == .charging ? chargingDetail(battery) : "按最近的掉电速度推算"
            if rate < 0 {
                display.icon = "arrow.down.right"
                display.tint = Theme.caution
            }
        } else {
            display.title = battery.state == .charging ? "充电" : "耗电速度"
            display.detail = battery.state == .charging ? "正在估算功率…" : "刷新几次后显示"
            if battery.state != .charging {
                display.icon = "arrow.down.right"
                display.tint = Theme.caution
            }
        }
        return display
    }

    private func chargingDetail(_ battery: BatterySample) -> String {
        guard let level = battery.level, let rate = battery.levelPerHour,
              let seconds = ChargeForecast.timeToFull(level: level, levelPerHour: rate) else { return "充电中" }
        return "约 \(Format.duration(seconds)) 充满"
    }

    private func cpuDisplay(_ cpu: CPUSample?) -> MetricDisplay {
        guard let cpu, cpu.isSystemWide else {
            return MetricDisplay(kind: self, title: "CPU", value: "--", unit: "", detail: cpu == nil ? "暂无数据" : "系统未开放整机数据", progress: nil, icon: "cpu", tint: Theme.cpu, source: .measured)
        }
        return MetricDisplay(
            kind: self,
            title: "CPU",
            value: String(format: "%.0f", cpu.usage * 100),
            unit: "%",
            detail: "\(cpu.coreCount) 核 · 整机",
            progress: cpu.usage,
            icon: "cpu",
            tint: Theme.cpu,
            source: .measured)
    }

    private func memoryDisplay(_ memory: MemorySample?) -> MetricDisplay {
        guard let memory else {
            return MetricDisplay(kind: self, title: "内存", value: "--", unit: "", detail: "暂无数据", progress: nil, icon: "memorychip", tint: Theme.memory, source: .measured)
        }
        let used = Format.memoryParts(memory.usedBytes)
        let total = Format.memoryParts(memory.totalBytes)
        return MetricDisplay(
            kind: self,
            title: "内存",
            value: used.value,
            unit: used.unit,
            detail: "已用 · 共 \(total.value) \(total.unit)",
            progress: memory.usedFraction,
            icon: "memorychip",
            tint: Theme.memory,
            source: .measured)
    }

    private func storageDisplay(_ storage: StorageSample?) -> MetricDisplay {
        guard let storage else {
            return MetricDisplay(kind: self, title: "存储", value: "--", unit: "", detail: "暂无数据", progress: nil, icon: "internaldrive", tint: Theme.storage, source: .measured)
        }
        let available = Format.storageParts(storage.availableBytes)
        let total = Format.storageParts(storage.totalBytes)
        return MetricDisplay(
            kind: self,
            title: "存储",
            value: available.value,
            unit: available.unit,
            detail: "可用 · 共 \(total.value) \(total.unit)",
            progress: storage.usedFraction,
            icon: "internaldrive",
            tint: Theme.storage,
            source: .measured)
    }

    private func networkDisplay(_ network: NetworkSample) -> MetricDisplay {
        let download = Format.speedParts(network.downloadBytesPerSecond)
        return MetricDisplay(
            kind: self,
            title: "网速 · \(network.connection.label)",
            value: download.value,
            unit: download.unit,
            detail: "↑ \(Format.speed(network.uploadBytesPerSecond))",
            progress: nil,
            icon: "arrow.down",
            tint: Theme.network,
            source: .measured)
    }

    private func thermalDisplay(_ thermal: ThermalLevel, lowPower: Bool) -> MetricDisplay {
        let detail: String
        if thermal.isThrottling {
            detail = "可能已降低性能"
        } else if lowPower {
            detail = "低电量模式中"
        } else {
            detail = "性能未受限"
        }
        return MetricDisplay(
            kind: self,
            title: "温控",
            value: thermal.label,
            unit: "",
            detail: detail,
            progress: Double(thermal.severity + 1) / 4,
            icon: "thermometer.medium",
            tint: Theme.thermalColor(thermal),
            source: .measured)
    }
}
