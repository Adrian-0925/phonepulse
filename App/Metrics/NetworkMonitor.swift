import Foundation
import Network

/// 实时网速：读取系统网卡的累计收发字节数（getifaddrs），两次采样相减再除以时间间隔。
/// 只统计 Wi-Fi（en0）和蜂窝（pdp_ip*）；VPN 的 utun 流量已经包含在物理网卡里，跳过以免重复计算。
final class NetworkMonitor {
    private(set) var connection: ConnectionType = .none

    private let pathMonitor = NWPathMonitor()
    /// if_data 里的计数器是 32 位的，超过 4 GB 会回绕，所以记下上次的原始值、只累加增量
    private var lastRaw: [String: (rx: UInt32, tx: UInt32)] = [:]
    private var lastSampleTime: TimeInterval?
    private var sessionWifiBytes: UInt64 = 0
    private var sessionCellularBytes: UInt64 = 0

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
        let delta = readInterfaces()
        let now = ProcessInfo.processInfo.systemUptime
        var download = 0.0
        var upload = 0.0
        if let lastSampleTime, now > lastSampleTime {
            download = Double(delta.rx) / (now - lastSampleTime)
            upload = Double(delta.tx) / (now - lastSampleTime)
        }
        lastSampleTime = now
        return NetworkSample(
            downloadBytesPerSecond: download,
            uploadBytesPerSecond: upload,
            sessionWifiBytes: sessionWifiBytes,
            sessionCellularBytes: sessionCellularBytes,
            connection: connection)
    }

    /// 退到后台时调用：回到前台后的第一次采样不计算速度，避免把后台期间的流量平均进去
    func pause() {
        lastSampleTime = nil
    }

    /// 返回自上次读取以来、已知接口上新增的字节数。第一次见到的接口只记录基准值。
    private func readInterfaces() -> (rx: UInt64, tx: UInt64) {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return (0, 0) }
        defer { freeifaddrs(head) }

        var totalRx: UInt64 = 0
        var totalTx: UInt64 = 0
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = pointer.pointee
            guard let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK),
                  let data = ifa.ifa_data else { continue }
            let name = String(cString: ifa.ifa_name)
            guard let kind = InterfaceKind(name: name) else { continue }

            let stats = data.assumingMemoryBound(to: if_data.self).pointee
            let rx = stats.ifi_ibytes
            let tx = stats.ifi_obytes
            defer { lastRaw[name] = (rx, tx) }
            guard let last = lastRaw[name] else { continue }

            // &- 是溢出减法，计数器回绕后也能得到正确的增量
            let deltaRx = UInt64(rx &- last.rx)
            let deltaTx = UInt64(tx &- last.tx)
            totalRx += deltaRx
            totalTx += deltaTx
            switch kind {
            case .wifi: sessionWifiBytes += deltaRx + deltaTx
            case .cellular: sessionCellularBytes += deltaRx + deltaTx
            }
        }
        return (totalRx, totalTx)
    }
}

private enum InterfaceKind {
    case wifi, cellular

    init?(name: String) {
        if name == "en0" {
            self = .wifi
        } else if name.hasPrefix("pdp_ip") {
            self = .cellular
        } else {
            return nil
        }
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
