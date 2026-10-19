import Foundation
import Observation
import UIKit
import WidgetKit

/// 真机诊断用的原始数据，诊断页和诊断报告读取它
struct EngineDiagnostics {
    var tickCount = 0
    /// 在后台（悬浮窗开着）时完成的采样次数
    var backgroundTickCount = 0
    /// 后台时相邻两次采样的最大间隔（按真实时间）。接近 1 秒说明后台一直在刷新，明显变大说明被系统暂停过
    var maxBackgroundGap: TimeInterval = 0
    var rawBatteryLevel: Float = -1
    var smallestBatteryStep: Double?
    var batteryChangePoints = 0
    var interfaces: [InterfaceReading] = []
}

/// 采样调度中心，也是唯一的数据源：每秒采一次所有指标，同一份结果分发给所有显示位置（见 distribute）。
///
/// 只要 App 在运行就会采样：在前台时，或者悬浮窗开着（系统因此让 App 在后台继续运行）时。
/// App 被系统挂起后无法采样，这是 iOS 的限制，见 README「后台运行与刷新」。
@MainActor
@Observable
final class MetricsEngine {
    let historyLength = 60

    private(set) var snapshot: MetricsSnapshot?
    private(set) var downloadHistory: [Double] = []
    private(set) var uploadHistory: [Double] = []
    private(set) var cpuHistory: [Double] = []
    private(set) var diagnostics = EngineDiagnostics()

    /// 悬浮窗的刷新回调（由 FloatingSpeedController 设置）
    @ObservationIgnored var onTick: ((MetricsSnapshot) -> Void)?

    private let network = NetworkMonitor()
    private let cpu = CPUMonitor()
    private let battery = BatteryMonitor()
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var ticksSinceSave = 0
    @ObservationIgnored private var lastTickDate: Date?
    /// 每隔多少次采样保存一次快照给小组件
    private let saveEvery = 30

    func start(interval: Duration = .seconds(1)) {
        guard loop == nil else { return }
        EventLog.shared.add("开始采样（App \(UIApplication.shared.applicationState.label)）")
        loop = Task { [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(for: interval)
            }
        }
    }

    func stop() {
        guard loop != nil else { return }
        EventLog.shared.add("停止采样")
        loop?.cancel()
        loop = nil
        lastTickDate = nil
        network.pause()
        cpu.pause()
        persist()
        LiveActivityService.shared.engineDidStop()
        ChargeSessionStore.shared.save()
    }

    private func tick() {
        let cpuSample = cpu.sample()
        let snapshot = MetricsSnapshot(
            timestamp: .now,
            network: network.sample(),
            cpu: cpuSample ?? self.snapshot?.cpu,
            memory: SystemProbe.memory(),
            battery: battery.sample(),
            storage: SystemProbe.storage(),
            thermal: SystemProbe.thermal)
        self.snapshot = snapshot

        Self.append(snapshot.network.downloadBytesPerSecond, to: &downloadHistory, limit: historyLength)
        Self.append(snapshot.network.uploadBytesPerSecond, to: &uploadHistory, limit: historyLength)
        if let cpuSample {
            Self.append(cpuSample.usage, to: &cpuHistory, limit: historyLength)
        }
        distribute(snapshot)

        let isBackground = UIApplication.shared.applicationState == .background
        updateDiagnostics(isBackground: isBackground)

        ticksSinceSave += 1
        if ticksSinceSave >= saveEvery {
            // 后台（悬浮窗开着）时刷新小组件会消耗系统给的刷新额度，只保存数据
            persist(reloadWidgets: !isBackground)
        }
    }

    /// 同一份采样结果分发给所有显示位置，各处显示的是同一秒的数据：
    /// - App 页面：读 snapshot 属性（SwiftUI 自动刷新）
    /// - 悬浮窗：每秒重画一帧
    /// - 灵动岛：显示内容有变化就推送
    /// - 充电记录：约每分钟记一个点
    private func distribute(_ snapshot: MetricsSnapshot) {
        onTick?(snapshot)
        LiveActivityService.shared.engineDidSample(snapshot)
        ChargeSessionStore.shared.record(snapshot)
    }

    private func updateDiagnostics(isBackground: Bool) {
        let now = Date.now
        var next = diagnostics
        next.tickCount += 1
        if isBackground {
            next.backgroundTickCount += 1
            if let lastTickDate {
                next.maxBackgroundGap = max(next.maxBackgroundGap, now.timeIntervalSince(lastTickDate))
            }
        }
        lastTickDate = now
        next.rawBatteryLevel = battery.rawLevel
        next.smallestBatteryStep = battery.smallestObservedStep
        next.batteryChangePoints = battery.changePointCount
        next.interfaces = network.lastReadings
        diagnostics = next
    }

    private func persist(reloadWidgets: Bool = true) {
        ticksSinceSave = 0
        guard let snapshot else { return }
        SharedStore.save(snapshot)
        if reloadWidgets {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    private static func append(_ value: Double, to history: inout [Double], limit: Int) {
        history.append(value)
        if history.count > limit {
            history.removeFirst(history.count - limit)
        }
    }
}
