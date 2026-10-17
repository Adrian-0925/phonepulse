import Foundation

/// 几种"电池容量"的区别：
/// - 设计容量：出厂标称值，机型静态规格（如 iPhone 15 Pro 为 3274 mAh）
/// - 最大容量百分比：电池老化后还剩多少，系统设置里能看到，但 App 读不到，只能由用户手动填写
/// - 当前满电容量 = 设计容量 × 最大容量百分比（计算值）
/// - 剩余电量 = 当前满电容量 × 当前电量百分比（估算值）
struct BatteryCapacity: Equatable {
    var designMAh: Int
    /// 0...1，nil 表示用户没有填写（按 100% 计算）
    var health: Double?

    var fullChargeMAh: Int {
        Int((Double(designMAh) * min(max(health ?? 1, 0), 1)).rounded())
    }

    func remainingMAh(level: Double) -> Int {
        Int((Double(fullChargeMAh) * min(max(level, 0), 1)).rounded())
    }
}
