import Foundation

/// 悬浮窗样式：两行各显示什么、用什么配色。只有 App 用，存在 UserDefaults.standard。
/// 悬浮窗的大小和位置由系统控制（双指捏合缩放、拖到边缘收起），App 只能决定画面里画什么
struct FloatingStyle: Equatable {
    enum Item: String, CaseIterable, Identifiable {
        case download, upload, battery, cpu, none

        var id: String { rawValue }

        var label: String {
            switch self {
            case .download: "下载速度"
            case .upload: "上传速度"
            case .battery: "电量"
            case .cpu: "CPU"
            case .none: "不显示"
            }
        }

        var shortLabel: String {
            switch self {
            case .download: "下载"
            case .upload: "上传"
            case .battery: "电量"
            case .cpu: "CPU"
            case .none: ""
            }
        }
    }

    enum Palette: String, CaseIterable, Identifiable {
        /// 每项一个颜色：下载蓝、上传橙、电量绿（充电时黄）、CPU 紫
        case colorful
        case white
        /// 终端风格的绿色
        case green

        var id: String { rawValue }

        var label: String {
            switch self {
            case .colorful: "彩色"
            case .white: "白色"
            case .green: "绿色"
            }
        }
    }

    var firstLine: Item
    var secondLine: Item
    var palette: Palette

    static let standard = FloatingStyle(firstLine: .download, secondLine: .upload, palette: .colorful)

    /// 第一行必须显示点什么
    static let firstLineItems: [Item] = [.download, .upload, .battery, .cpu]
    static let secondLineItems: [Item] = Item.allCases

    /// 实际要画的行：第二行选「不显示」时只有一行，字会更大
    var lines: [Item] {
        secondLine == .none ? [firstLine] : [firstLine, secondLine]
    }

    /// 设置里显示的简短说明，如「下载 / 上传 · 彩色」
    var summary: String {
        lines.map(\.shortLabel).joined(separator: " / ") + " · " + palette.label
    }

    /// 某一行画出来的文字
    static func text(for item: Item, snapshot: MetricsSnapshot?) -> String {
        switch item {
        case .download:
            return "↓ " + Format.speed(snapshot?.network.downloadBytesPerSecond ?? 0)
        case .upload:
            return "↑ " + Format.speed(snapshot?.network.uploadBytesPerSecond ?? 0)
        case .battery:
            guard let battery = snapshot?.battery, let level = battery.level else { return "电量 --" }
            let percent = Format.batteryPercent(level)
            switch battery.state {
            case .charging:
                // 有估算功率就带上（≈ 表示估算）；还在采集时只显示电量
                let readout = PowerReadout(battery: battery, now: snapshot?.timestamp ?? .now, context: .charging)
                return readout.hasResult && readout.value.hasPrefix("≈") ? "⚡ \(percent) \(readout.value)" : "⚡ \(percent)"
            case .full:
                return "⚡ \(percent)"
            case .unplugged, .unknown:
                return "电量 \(percent)"
            }
        case .cpu:
            guard let cpu = snapshot?.cpu else { return "CPU --" }
            return "CPU " + Format.percent(cpu.usage)
        case .none:
            return ""
        }
    }
}

extension FloatingStyle {
    private enum Key {
        static let firstLine = "floatingFirstLine"
        static let secondLine = "floatingSecondLine"
        static let palette = "floatingPalette"
    }

    static func load(from defaults: UserDefaults = .standard) -> FloatingStyle {
        var first = defaults.string(forKey: Key.firstLine).flatMap(Item.init(rawValue:)) ?? standard.firstLine
        if first == .none {
            first = standard.firstLine
        }
        return FloatingStyle(
            firstLine: first,
            secondLine: defaults.string(forKey: Key.secondLine).flatMap(Item.init(rawValue:)) ?? standard.secondLine,
            palette: defaults.string(forKey: Key.palette).flatMap(Palette.init(rawValue:)) ?? standard.palette)
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(firstLine.rawValue, forKey: Key.firstLine)
        defaults.set(secondLine.rawValue, forKey: Key.secondLine)
        defaults.set(palette.rawValue, forKey: Key.palette)
    }
}
