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
