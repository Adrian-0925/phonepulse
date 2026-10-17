import Foundation
import Observation
import WidgetKit

/// 采样调度中心：App 在前台时每秒采一次所有指标，保留最近 60 秒的曲线，
/// 并定期把最新快照写进 App Group 供小组件读取。
@MainActor
@Observable
final class MetricsEngine {
    let historyLength = 60

    private(set) var snapshot: MetricsSnapshot?
    private(set) var downloadHistory: [Double] = []
    private(set) var uploadHistory: [Double] = []
    private(set) var cpuHistory: [Double] = []

    private let network = NetworkMonitor()
    private let cpu = CPUMonitor()
    private let memory = MemoryMonitor()
    private let battery = BatteryMonitor()
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var ticksSinceSave = 0
    /// 每隔多少次采样保存一次快照给小组件
    private let saveEvery = 30

    func start(interval: Duration = .seconds(1)) {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(for: interval)
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
        network.pause()
        cpu.pause()
        persist()
    }

    private func tick() {
        let cpuSample = cpu.sample()
        let snapshot = MetricsSnapshot(
            timestamp: .now,
            network: network.sample(),
            cpu: cpuSample ?? self.snapshot?.cpu,
            memory: memory.sample(),
            battery: battery.sample(),
            storage: StorageProbe.sample(),
            thermal: ThermalLevel(ProcessInfo.processInfo.thermalState))
        self.snapshot = snapshot

        Self.append(snapshot.network.downloadBytesPerSecond, to: &downloadHistory, limit: historyLength)
        Self.append(snapshot.network.uploadBytesPerSecond, to: &uploadHistory, limit: historyLength)
        if let cpuSample {
            Self.append(cpuSample.usage, to: &cpuHistory, limit: historyLength)
        }

        ticksSinceSave += 1
        if ticksSinceSave >= saveEvery {
            persist()
        }
    }

    private func persist() {
        ticksSinceSave = 0
        guard let snapshot else { return }
        SharedStore.save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private static func append(_ value: Double, to history: inout [Double], limit: Int) {
        history.append(value)
        if history.count > limit {
            history.removeFirst(history.count - limit)
        }
    }
}
