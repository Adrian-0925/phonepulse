#if !WIDGET_EXTENSION
import ActivityKit
import Foundation
import Observation
import UIKit

/// 管理灵动岛 / 锁屏实时活动。只编译进 App（扩展里不能开启实时活动）。
///
/// 刷新规则：
/// - 数据和悬浮窗来自同一份每秒采样（MetricsEngine）。只要显示的内容变了就推送，所以和悬浮窗一样最快每秒更新一次；
///   内容没变时每 15 秒推一次，让「更新时间」保持最新。实际显示还取决于系统，iOS 可能会合并过于频繁的更新。
/// - App 在前台，或悬浮窗开着（App 因此在后台继续运行）时才能更新。
///   App 被系统挂起后无法更新，显示最后一次的数据并标「已暂停」；充满倒计时和进度条由系统自己走动。
/// - 远程推送更新需要付费账号和服务器，而且服务器拿不到手机状态，所以不采用。
/// - 系统最多显示 8 小时，之后自动结束。
@MainActor
@Observable
final class LiveActivityService {
    static let shared = LiveActivityService()

    /// 内容没变时多久推一次
    private static let heartbeat: TimeInterval = 15

    private(set) var isRunning = false
    private(set) var focus: LiveActivityFocus = .auto
    private(set) var lastError: String?

    /// 诊断用：本次运行推送了多少次、最近一次推送的时间、系统处理一次更新花了多久
    private(set) var pushCount = 0
    private(set) var lastPushDate: Date?
    private(set) var lastUpdateDuration: TimeInterval?

    @ObservationIgnored private var latestState: StatusActivityAttributes.ContentState?
    @ObservationIgnored private var lastPushedState: StatusActivityAttributes.ContentState?
    @ObservationIgnored private var recentPushes: [Date] = []
    @ObservationIgnored private var queuedContent: ActivityContent<StatusActivityAttributes.ContentState>?
    @ObservationIgnored private var updateTask: Task<Void, Never>?

    private init() {
        let saved = SharedStore.defaults.string(forKey: SharedStore.Key.liveActivityFocus) ?? ""
        focus = LiveActivityFocus(rawValue: saved) ?? .auto
        isRunning = !Activity<StatusActivityAttributes>.activities.isEmpty
    }

    var areActivitiesEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    /// 诊断用：最近 60 秒推送了几次
    var pushesInLastMinute: Int {
        recentPushes.filter { Date.now.timeIntervalSince($0) <= 60 }.count
    }

    func toggle() async throws {
        if Activity<StatusActivityAttributes>.activities.isEmpty {
            try start()
        } else {
            await stop()
        }
    }

    func start() throws {
        guard Activity<StatusActivityAttributes>.activities.isEmpty else {
            isRunning = true
            return
        }
        var state = latestState ?? Self.stateFromProbes(focus: focus)
        state.focus = focus
        do {
            _ = try Activity.request(
                attributes: StatusActivityAttributes(),
                content: ActivityContent(state: state, staleDate: Self.staleDate()),
                pushType: nil)
            isRunning = true
            lastError = nil
            lastPushedState = state
            recordPush()
            EventLog.shared.add("灵动岛已开启（\(focus.label)）")
        } catch {
            lastError = error.localizedDescription
            EventLog.shared.add("灵动岛开启失败：\(error.localizedDescription)")
            throw error
        }
    }

    func stop() async {
        for activity in Activity<StatusActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        isRunning = false
        lastPushedState = nil
        EventLog.shared.add("灵动岛已关闭")
    }

    func setFocus(_ newFocus: LiveActivityFocus) {
        guard newFocus != focus else { return }
        focus = newFocus
        SharedStore.defaults.set(newFocus.rawValue, forKey: SharedStore.Key.liveActivityFocus)
        if var state = latestState {
            state.focus = newFocus
            latestState = state
            push(state)
        }
    }

    /// 灵动岛上的「刷新」按钮：App 正在采样就直接推最新的；App 被系统暂停了就现场读一次（约 1 秒）。
    /// 由系统在 App 进程里执行，App 被暂停时会被短暂唤醒，不用打开 App。
    func refresh() async {
        guard !Activity<StatusActivityAttributes>.activities.isEmpty else { return }
        if let latestState, latestState.isLive, Date.now.timeIntervalSince(latestState.updatedAt) < 3 {
            push(latestState)
        } else {
            let reading = await InstantSampler.read()
            let state = StatusActivityAttributes.ContentState(reading: reading, focus: focus, previous: latestState)
            latestState = state
            push(state)
            EventLog.shared.add("灵动岛手动刷新（App 没在采样，现场读取了一次）")
        }
        // 执行完 App 可能马上又被暂停，等这次更新送达再返回
        await updateTask?.value
    }

    /// 灵动岛上的「切换」按钮：自动 → 电池 → 网速 → 性能 → 自动
    func cycleFocus() async {
        let all = LiveActivityFocus.allCases
        let index = all.firstIndex(of: focus) ?? 0
        setFocus(all[(index + 1) % all.count])
        if latestState?.isLive == true {
            await updateTask?.value
        } else {
            // App 没在采样（比如刚被唤醒），顺便现场读一次，免得切过去看到的是旧数据
            await refresh()
        }
    }

    /// App 每次采样后调用（每秒一次，和悬浮窗同一份数据）
    func engineDidSample(_ snapshot: MetricsSnapshot) {
        let state = StatusActivityAttributes.ContentState(snapshot: snapshot, focus: focus, isLive: true)
        latestState = state
        let running = !Activity<StatusActivityAttributes>.activities.isEmpty
        if running != isRunning {
            // 用户可能在锁屏上划掉了，或者系统到时间自动结束了
            isRunning = running
        }
        guard running else { return }

        let contentChanged = state.displaySignature != lastPushedState?.displaySignature
        let heartbeatDue = Date.now.timeIntervalSince(lastPushDate ?? .distantPast) >= Self.heartbeat
        if contentChanged || heartbeatDue {
            push(state)
        }
    }

    /// App 停止采样时调用：标记为「已暂停」。App 马上会被系统挂起，所以申请一点后台时间确保这次更新送达
    func engineDidStop() {
        guard var state = latestState, !Activity<StatusActivityAttributes>.activities.isEmpty else { return }
        state.isLive = false
        latestState = state
        let backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "LiveActivityPause")
        push(state)
        Task {
            await self.updateTask?.value
            UIApplication.shared.endBackgroundTask(backgroundTask)
        }
    }

    /// 推送一次更新。上一次还没处理完时只保留最新的一份，处理完马上接着推，不会越积越多
    private func push(_ state: StatusActivityAttributes.ContentState) {
        lastPushedState = state
        recordPush()
        queuedContent = ActivityContent(state: state, staleDate: Self.staleDate())
        guard updateTask == nil else { return }
        updateTask = Task { [weak self] in
            while let self, let content = self.queuedContent {
                self.queuedContent = nil
                let started = Date.now
                for activity in Activity<StatusActivityAttributes>.activities {
                    await activity.update(content)
                }
                self.lastUpdateDuration = Date.now.timeIntervalSince(started)
            }
            self?.updateTask = nil
        }
    }

    private func recordPush() {
        let now = Date.now
        lastPushDate = now
        pushCount += 1
        recentPushes.append(now)
        recentPushes.removeAll { now.timeIntervalSince($0) > 60 }
    }

    /// 超过这个时间没更新，系统会把内容标记为过期（界面上显示「可能已过期」）
    private static func staleDate() -> Date {
        Date.now.addingTimeInterval(5 * 60)
    }

    /// 从小组件按钮开启时 App 可能没在采样，先用当下能直接读到的数据
    private static func stateFromProbes(focus: LiveActivityFocus) -> StatusActivityAttributes.ContentState {
        let reading = BatteryProbe.read()
        return StatusActivityAttributes.ContentState(
            focus: focus,
            batteryLevel: reading.level,
            batteryState: reading.state,
            powerWatts: nil,
            levelPerHour: nil,
            fullDate: nil,
            downloadBytesPerSecond: 0,
            uploadBytesPerSecond: 0,
            cpuUsage: nil,
            thermal: SystemProbe.thermal,
            updatedAt: .now,
            isLive: false)
    }
}
#endif
