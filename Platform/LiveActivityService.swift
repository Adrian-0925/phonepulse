#if !WIDGET_EXTENSION
import ActivityKit
import Foundation
import Observation

/// 管理灵动岛 / 锁屏实时活动。只编译进 App（扩展里不能开启实时活动）。
///
/// 刷新规则（iOS 的限制）：
/// - App 在前台或悬浮窗开着时，跟随采样实时更新（网速每 2 秒，其他每 10 秒，电量变化时立即更新）
/// - App 被系统挂起后无法更新，显示最后一次的数据并标明更新时间；充满倒计时和进度条由系统自己走动
/// - 远程推送更新需要付费账号和服务器，而且服务器拿不到手机状态，所以不采用
/// - 系统最多显示 8 小时，之后自动结束
@MainActor
@Observable
final class LiveActivityService {
    static let shared = LiveActivityService()

    private(set) var isRunning = false
    private(set) var focus: LiveActivityFocus = .auto
    private(set) var lastError: String?

    @ObservationIgnored private var latestState: StatusActivityAttributes.ContentState?
    @ObservationIgnored private var lastPushedState: StatusActivityAttributes.ContentState?
    @ObservationIgnored private var lastPushDate: Date = .distantPast

    private init() {
        let saved = SharedStore.defaults.string(forKey: SharedStore.Key.liveActivityFocus) ?? ""
        focus = LiveActivityFocus(rawValue: saved) ?? .auto
        isRunning = !Activity<StatusActivityAttributes>.activities.isEmpty
    }

    var areActivitiesEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
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
            lastPushDate = .now
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

    /// App 每次采样后调用
    func engineDidSample(_ snapshot: MetricsSnapshot) {
        let state = StatusActivityAttributes.ContentState(snapshot: snapshot, focus: focus, isLive: true)
        latestState = state
        let running = !Activity<StatusActivityAttributes>.activities.isEmpty
        if running != isRunning {
            // 用户可能在锁屏上划掉了，或者系统到时间自动结束了
            isRunning = running
        }
        guard running else { return }

        let interval: TimeInterval = state.effectiveFocus == .network ? 2 : 10
        let batteryChanged = state.batteryLevel != lastPushedState?.batteryLevel
            || state.batteryState != lastPushedState?.batteryState
        if batteryChanged || Date.now.timeIntervalSince(lastPushDate) >= interval {
            push(state)
        }
    }

    /// App 停止采样时调用：标记为"已暂停"，界面上会提示数据不再实时
    func engineDidStop() {
        guard var state = latestState, !Activity<StatusActivityAttributes>.activities.isEmpty else { return }
        state.isLive = false
        latestState = state
        push(state)
    }

    private func push(_ state: StatusActivityAttributes.ContentState) {
        lastPushedState = state
        lastPushDate = .now
        let content = ActivityContent(state: state, staleDate: Self.staleDate())
        Task {
            for activity in Activity<StatusActivityAttributes>.activities {
                await activity.update(content)
            }
        }
    }

    /// 超过这个时间没更新，系统会把内容标记为过期（界面上显示"可能已过期"）
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
