import Foundation

enum Format {
    /// 网速，十进制单位（与运营商、测速软件一致）
    static func speed(_ bytesPerSecond: Double) -> String {
        let units = ["B/s", "KB/s", "MB/s", "GB/s"]
        var value = max(bytesPerSecond, 0)
        var index = 0
        while value >= 1000, index < units.count - 1 {
            value /= 1000
            index += 1
        }
        let digits = index == 0 || value >= 100 ? 0 : (value >= 10 ? 1 : 2)
        return "\(String(format: "%.\(digits)f", value)) \(units[index])"
    }

    static func mbps(_ value: Double) -> String {
        "\(String(format: value >= 100 ? "%.0f" : "%.1f", value)) Mbps"
    }

    static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    static func bytes(_ value: UInt64) -> String {
        bytes(Int64(clamping: value))
    }

    static func percent(_ fraction: Double) -> String {
        fraction.formatted(.percent.precision(.fractionLength(0)))
    }

    static func watts(_ value: Double) -> String {
        String(format: "%.1f W", value)
    }
}
