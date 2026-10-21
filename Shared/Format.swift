import Foundation

enum Format {
    /// 网速，十进制单位（与运营商、测速软件一致），数值和单位分开，方便小组件把数字放大
    static func speedParts(_ bytesPerSecond: Double) -> (value: String, unit: String) {
        let units = ["B/s", "KB/s", "MB/s", "GB/s"]
        var value = max(bytesPerSecond, 0)
        var index = 0
        while value >= 1000, index < units.count - 1 {
            value /= 1000
            index += 1
        }
        let digits = index == 0 || value >= 100 ? 0 : (value >= 10 ? 1 : 2)
        return (String(format: "%.\(digits)f", value), units[index])
    }

    static func speed(_ bytesPerSecond: Double) -> String {
        let parts = speedParts(bytesPerSecond)
        return "\(parts.value) \(parts.unit)"
    }

    /// 灵动岛等极窄位置用的网速，如 1.2M、850K
    static func compactSpeed(_ bytesPerSecond: Double) -> String {
        let units = ["B", "K", "M", "G"]
        var value = max(bytesPerSecond, 0)
        var index = 0
        while value >= 1000, index < units.count - 1 {
            value /= 1000
            index += 1
        }
        let text = index == 0 || value >= 10 ? String(format: "%.0f", value) : String(format: "%.1f", value)
        return text + units[index]
    }

    static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    static func bytes(_ value: UInt64) -> String {
        bytes(Int64(clamping: value))
    }

    /// 存储按十进制（与系统设置里显示的一致）
    static func storageParts(_ bytes: Int64) -> (value: String, unit: String) {
        sizeParts(Double(bytes), base: 1000)
    }

    /// 内存按二进制（6 GB 内存显示为 6.0 GB，而不是 6.4 GB）
    static func memoryParts(_ bytes: UInt64) -> (value: String, unit: String) {
        sizeParts(Double(bytes), base: 1024)
    }

    /// 电量数字（不带 %），四舍五入到整数。所有显示电量的地方都用它，保证 App、小组件、灵动岛取整方式一致
    static func batteryNumber(_ level: Double) -> String {
        String(Int((min(max(level, 0), 1) * 100).rounded()))
    }

    /// 电量百分比，如 78%
    static func batteryPercent(_ level: Double) -> String {
        batteryNumber(level) + "%"
    }

    static func percent(_ fraction: Double) -> String {
        fraction.formatted(.percent.precision(.fractionLength(0)))
    }

    static func watts(_ value: Double) -> String {
        String(format: "%.1f W", value)
    }

    /// 估算功率的数字（不带单位），保留两位有效数字：18 W、4.3 W。
    /// 估算本身有约 ±10% 的误差（电压按 3.85V 计、容量按手动填写），多写小数位反而误导
    static func estimatedWattsNumber(_ value: Double) -> String {
        let magnitude = abs(value)
        return String(format: magnitude >= 9.95 ? "%.0f" : "%.1f", magnitude)
    }

    /// 估算功率，如 18 W、4.3 W（取绝对值，方向由文案说明）
    static func estimatedWatts(_ value: Double) -> String {
        estimatedWattsNumber(value) + " W"
    }

    /// 多久以前，如 刚刚、35 秒前、3 分钟前
    static func ago(_ seconds: TimeInterval) -> String {
        let value = max(seconds, 0)
        if value < 5 { return "刚刚" }
        if value < 60 { return "\(Int(value)) 秒前" }
        if value < 3600 { return "\(Int(value / 60)) 分钟前" }
        return "\(Int(value / 3600)) 小时前"
    }

    /// 已经过了多久（向下取整，不会把 90 秒说成 2 分钟），如 35 秒、1 分钟、1 小时 5 分
    static func elapsed(_ seconds: TimeInterval) -> String {
        let value = max(seconds, 0)
        if value < 60 { return "\(Int(value)) 秒" }
        let minutes = Int(value / 60)
        if minutes < 60 { return "\(minutes) 分钟" }
        return minutes % 60 == 0 ? "\(minutes / 60) 小时" : "\(minutes / 60) 小时 \(minutes % 60) 分"
    }

    /// 电量变化速度，如 +18%/h、-8%/h
    static func levelRate(_ perHour: Double) -> String {
        String(format: "%+.0f%%/h", perHour * 100)
    }

    /// 时长，如 25 分钟、1 小时 20 分
    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        if minutes < 60 {
            return "\(minutes) 分钟"
        }
        return minutes % 60 == 0 ? "\(minutes / 60) 小时" : "\(minutes / 60) 小时 \(minutes % 60) 分"
    }

    private static func sizeParts(_ bytes: Double, base: Double) -> (value: String, unit: String) {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = max(bytes, 0)
        var index = 0
        while value >= base, index < units.count - 1 {
            value /= base
            index += 1
        }
        let digits = index == 0 || value >= 100 ? 0 : 1
        return (String(format: "%.\(digits)f", value), units[index])
    }
}
