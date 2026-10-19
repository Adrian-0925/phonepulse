import AppIntents
import SwiftUI
import WidgetKit

/// 控制中心按钮（iOS 18 起）：开关灵动岛、刷新数据、切换灵动岛显示内容。
///
/// 三个按钮执行的都是和灵动岛、小组件同一套意图（Platform/Intents.swift），由系统在 App 进程里执行，
/// 走 LiveActivityService 的同一套开启 / 刷新 / 切换逻辑，所以 App、小组件、灵动岛的状态是一致的。
///
/// 为什么「灵动岛」是按钮而不是开关：开关要在小组件扩展里读到「灵动岛开着没有」。扩展读不到 App 的实时活动，
/// 只能靠 App Group 共享存储；免费账号侧载时 App Group 不可用，开关会一直显示「关」。所以用按钮：
/// App Group 可用时按钮名称显示当前状态（开启 / 结束），不可用时显示「开关灵动岛」，点一下灵动岛出现或消失就是反馈。
enum ControlKind {
    static let liveActivity = "io.github.adrian-0925.phonepulse.control.liveActivity"
    static let refresh = "io.github.adrian-0925.phonepulse.control.refresh"
    static let cycleFocus = "io.github.adrian-0925.phonepulse.control.cycleFocus"
}

/// 控制中心按钮上显示的状态；读不到时（没有 App Group）为 nil
struct LiveActivityControlValue: Equatable, Sendable {
    var isRunning: Bool?
    var focus: LiveActivityFocus?

    static var current: LiveActivityControlValue {
        guard SharedStore.isAppGroupAvailable else { return LiveActivityControlValue(isRunning: nil, focus: nil) }
        let defaults = SharedStore.defaults
        let focus = defaults.string(forKey: SharedStore.Key.liveActivityFocus).flatMap(LiveActivityFocus.init(rawValue:)) ?? .auto
        return LiveActivityControlValue(isRunning: defaults.bool(forKey: SharedStore.Key.liveActivityRunning), focus: focus)
    }

    var toggleTitle: String {
        switch isRunning {
        case true?: "结束灵动岛"
        case false?: "开启灵动岛"
        case nil: "开关灵动岛"
        }
    }

    var toggleIcon: String {
        isRunning == true ? "capsule.fill" : "capsule"
    }

    var focusTitle: String {
        guard let focus else { return "切换灵动岛内容" }
        return "灵动岛：\(focus.label)"
    }
}

@available(iOS 18.0, *)
struct LiveActivityControlProvider: ControlValueProvider {
    var previewValue: LiveActivityControlValue {
        LiveActivityControlValue(isRunning: false, focus: .auto)
    }

    func currentValue() async throws -> LiveActivityControlValue {
        .current
    }
}

@available(iOS 18.0, *)
struct LiveActivityControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: ControlKind.liveActivity, provider: LiveActivityControlProvider()) { value in
            ControlWidgetButton(action: ToggleLiveActivityIntent()) {
                Label(value.toggleTitle, systemImage: value.toggleIcon)
            }
        }
        .displayName("灵动岛开关")
        .description("开启或结束灵动岛上的手机状态显示，不用打开 App。")
    }
}

@available(iOS 18.0, *)
struct RefreshStatusControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: ControlKind.refresh) {
            ControlWidgetButton(action: RefreshAllIntent()) {
                Label("刷新手机状态", systemImage: "arrow.clockwise")
            }
        }
        .displayName("刷新手机状态")
        .description("现场读一次电量、网速和 CPU，更新灵动岛和小组件。")
    }
}

@available(iOS 18.0, *)
struct CycleFocusControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: ControlKind.cycleFocus, provider: LiveActivityControlProvider()) { value in
            ControlWidgetButton(action: CycleLiveActivityFocusIntent()) {
                Label(value.focusTitle, systemImage: "arrow.left.arrow.right")
            }
        }
        .displayName("切换灵动岛内容")
        .description("在自动、电池、网速、性能之间切换；灵动岛没开时会先开启。")
    }
}
