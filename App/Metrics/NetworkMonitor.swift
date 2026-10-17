import Foundation
import Network

/// 实时网速：读取系统网卡的累计收发字节数，两次采样相减再除以时间间隔。
/// 读数在 Platform/SystemProbes.swift，增量计算（回绕、接口重置、Wi-Fi/蜂窝分类）在 Core/TrafficCounter.swift。
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
        lastReadings = SystemProbe.interfaces()
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
}
