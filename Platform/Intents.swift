import AppIntents
import WidgetKit

/// 小组件上的刷新按钮：点一下立即重新读取数据（不用打开 App）
struct RefreshStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "刷新手机状态"
    static var description = IntentDescription("立即刷新 PhonePulse 小组件上的数据。")
    static var isDiscoverable = false

    func perform() async throws -> some IntentResult {
        // 按钮意图执行完后，系统会自动重新生成这个小组件的内容
        .result()
    }
}

/// 开关灵动岛。可以放在小组件按钮上，也能在「快捷指令」里使用（比如绑定到操作按钮）。
/// 实时活动意图由系统在 App 进程里执行，所以从小组件开启时不需要打开 App；
/// 小组件扩展里只需要这个类型本身，perform 的实际逻辑只编译进 App。
struct ToggleLiveActivityIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "开关 PhonePulse 灵动岛"
    static var description = IntentDescription("开启或关闭灵动岛上的手机状态显示。")

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        try await LiveActivityService.shared.toggle()
        #endif
        return .result()
    }
}

/// 灵动岛上的「刷新」按钮：App 被系统暂停时，系统会短暂唤醒 App 现场读一次数据并更新灵动岛
struct RefreshLiveActivityIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "刷新 PhonePulse 灵动岛"
    static var description = IntentDescription("立即读取一次手机状态并更新灵动岛。")

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        await LiveActivityService.shared.refresh()
        #endif
        return .result()
    }
}

/// 控制中心「刷新」：现场读一次数据，更新灵动岛（开着的话）和所有小组件。在 App 进程里执行，不用打开 App
struct RefreshAllIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "刷新 PhonePulse 数据"
    static var description = IntentDescription("立即读取一次手机状态，更新灵动岛和小组件。")

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        await LiveActivityService.shared.refreshEverything()
        #endif
        return .result()
    }
}

/// 快捷指令自动化「充电器 → 已连接」时运行：记下插电的确切时间和电量，并开启灵动岛（可在动作里关掉）。
/// App 没开时也能把每次充电的起点记下来；由系统在 App 进程里执行，不用打开 App
struct ChargerConnectedIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "PhonePulse 已插电"
    static var description = IntentDescription("放在「充电器已连接」自动化里：记录这次充电的开始，并开启灵动岛显示电量、估算功率和充满倒计时。")

    @Parameter(title: "同时开启灵动岛", default: true)
    var startsLiveActivity: Bool

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        let battery = BatteryProbe.read()
        ChargeSessionStore.shared.chargerConnected(
            level: battery.level,
            capacityMAh: BatterySettings.current.capacity?.fullChargeMAh,
            thermal: SystemProbe.thermal)
        if startsLiveActivity {
            do {
                try LiveActivityService.shared.start()
                await LiveActivityService.shared.refresh()
            } catch {
                // 实时活动被关闭等情况：start 里已记录原因，充电照样记录
            }
        }
        #endif
        return .result()
    }
}

/// 快捷指令自动化「充电器 → 已断开」时运行：以这一刻结束这次充电记录，并结束灵动岛（可在动作里关掉）
struct ChargerDisconnectedIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "PhonePulse 已拔电"
    static var description = IntentDescription("放在「充电器已断开」自动化里：记录这次充电的结束，并结束灵动岛。")

    @Parameter(title: "同时结束灵动岛", default: true)
    var endsLiveActivity: Bool

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        ChargeSessionStore.shared.chargerDisconnected(level: BatteryProbe.read().level)
        if endsLiveActivity {
            // 不看 isRunning：App 刚被唤醒时它可能还是旧值，stop 本身没开着就什么都不做
            await LiveActivityService.shared.stop()
        } else {
            await LiveActivityService.shared.refresh()
        }
        #endif
        return .result()
    }
}

/// 灵动岛和控制中心上的「切换」按钮：自动 → 电池 → 网速 → 性能。灵动岛没开时会先开启
struct CycleLiveActivityFocusIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "切换 PhonePulse 灵动岛显示内容"
    static var description = IntentDescription("在自动、电池、网速、性能之间切换灵动岛重点显示的内容；灵动岛没开时会先开启。")

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        await LiveActivityService.shared.cycleFocus()
        #endif
        return .result()
    }
}
