import Foundation

/// host_statistics(HOST_CPU_LOAD_INFO) 返回的累计 CPU tick（32 位，会回绕）
struct CPUTicks: Equatable {
    var user: UInt32
    var system: UInt32
    var idle: UInt32
    var nice: UInt32
}

struct CPULoad: Equatable {
    var usage: Double
    var user: Double
    var system: Double

    /// 两次读数之间的占用比例；tick 完全没变化时返回 nil。nice 计入用户态。
    init?(from old: CPUTicks, to new: CPUTicks) {
        let user = Double(new.user &- old.user) + Double(new.nice &- old.nice)
        let system = Double(new.system &- old.system)
        let idle = Double(new.idle &- old.idle)
        let total = user + system + idle
        guard total > 0 else { return nil }
        self.usage = (user + system) / total
        self.user = user / total
        self.system = system / total
    }
}
