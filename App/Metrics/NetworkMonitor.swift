import Foundation
import Network

/// 实时网速：读取系统网卡的累计收发字节数（getifaddrs），两次采样相减再除以时间间隔。
/// 增量计算（回绕、接口重置、Wi-Fi/蜂窝分类）在 Core/TrafficCounter.swift，有单元测试。
final class NetworkMonitor {
    private(set) var connection: ConnectionType = .none
    /// 最近一次读到的所有网卡原始计数，诊断页用
    private(set) var lastReadings: [InterfaceReading] = []

    private let pathMonitor = NWPathMonitor()
    private var counter = TrafficCounter()
    private var lastSampleTime: TimeInterval?

    init() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            self?.connection = ConnectionType(path)
        }
        pathMonitor.start(queue: .main)
    }

    deinit {
        pathMonitor.cancel()
    }

    func sample() -> NetworkSample {
        lastReadings = Self.readInterfaces()
        let delta = counter.update(with: lastReadings)
        let now = ProcessInfo.processInfo.systemUptime
        var download = 0.0
        var upload = 0.0
        if let lastSampleTime, now > lastSampleTime {
            download = Double(delta.received) / (now - lastSampleTime)
            upload = Double(delta.sent) / (now - lastSampleTime)
        }
        lastSampleTime = now
        return NetworkSample(
            downloadBytesPerSecond: download,
            uploadBytesPerSecond: upload,
            sessionWifiBytes: counter.sessionWifiBytes,
            sessionCellularBytes: counter.sessionCellularBytes,
            connection: connection)
    }

    /// 退到后台时调用：回到前台后的第一次采样不计算速度，避免把后台期间的流量平均进去
    func pause() {
        lastSampleTime = nil
    }

    private static func readInterfaces() -> [InterfaceReading] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }

        var readings: [InterfaceReading] = []
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = pointer.pointee
            guard let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK),
                  let data = ifa.ifa_data else { continue }
            let stats = data.assumingMemoryBound(to: if_data.self).pointee
            readings.append(InterfaceReading(
                name: String(cString: ifa.ifa_name),
                receivedBytes: stats.ifi_ibytes,
                sentBytes: stats.ifi_obytes))
        }
        return readings
    }
}

private extension ConnectionType {
    init(_ path: NWPath) {
        guard path.status == .satisfied else {
            self = .none
            return
        }
        if path.usesInterfaceType(.wifi) {
            self = .wifi
        } else if path.usesInterfaceType(.cellular) {
            self = .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            self = .wired
        } else {
            self = .other
        }
    }
}
