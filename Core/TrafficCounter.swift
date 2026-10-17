import Foundation

/// 一个网卡的原始累计计数（来自 getifaddrs 的 if_data，32 位，会回绕）
struct InterfaceReading: Equatable {
    var name: String
    var receivedBytes: UInt32
    var sentBytes: UInt32
}

enum InterfaceKind: Equatable {
    case wifi, cellular

    /// en0 = Wi-Fi，pdp_ip* = 蜂窝。utun（VPN）等接口不统计，它们的流量已经算在物理网卡里了。
    init?(interfaceName name: String) {
        if name == "en0" {
            self = .wifi
        } else if name.hasPrefix("pdp_ip") {
            self = .cellular
        } else {
            return nil
        }
    }
}

/// 把网卡的累计计数换算成"自上次读取以来的增量"。纯计算，不碰系统 API，方便单元测试。
struct TrafficCounter {
    struct Delta: Equatable {
        var received: UInt64
        var sent: UInt64
    }

    /// 计数变小时，增量不超过这个值就当作 32 位回绕，否则当作接口被重置（比如开关飞行模式）
    static let wrapThreshold: UInt64 = 1 << 30

    private(set) var sessionWifiBytes: UInt64 = 0
    private(set) var sessionCellularBytes: UInt64 = 0
    private var last: [String: InterfaceReading] = [:]

    /// 第一次见到的接口只记录基准值、不计入增量，否则开机以来的流量会被当成一秒内的网速。
    mutating func update(with readings: [InterfaceReading]) -> Delta {
        var delta = Delta(received: 0, sent: 0)
        for reading in readings {
            guard let kind = InterfaceKind(interfaceName: reading.name) else { continue }
            defer { last[reading.name] = reading }
            guard let previous = last[reading.name] else { continue }

            let received = Self.increment(from: previous.receivedBytes, to: reading.receivedBytes)
            let sent = Self.increment(from: previous.sentBytes, to: reading.sentBytes)
            delta.received += received
            delta.sent += sent
            switch kind {
            case .wifi: sessionWifiBytes += received + sent
            case .cellular: sessionCellularBytes += received + sent
            }
        }
        return delta
    }

    static func increment(from old: UInt32, to new: UInt32) -> UInt64 {
        if new >= old {
            return UInt64(new - old)
        }
        let wrapped = UInt64(UInt32.max - old) + UInt64(new) + 1
        return wrapped <= wrapThreshold ? wrapped : UInt64(new)
    }
}
