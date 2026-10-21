import SwiftUI

@main
struct PhonePulseApp: App {
    /// 只用来控制屏幕方向（充电大屏横屏，其他页面竖屏）
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var engine: MetricsEngine
    @State private var floating: FloatingSpeedController
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let engine = MetricsEngine()
        _engine = State(initialValue: engine)
        _floating = State(initialValue: FloatingSpeedController(engine: engine))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(engine)
                .environment(floating)
        }
        // iOS 不允许 App 在后台持续运行，所以只在前台采样，退到后台时保存快照给小组件。
        // 例外：悬浮窗开着时系统允许 App 继续运行，这时不停止采样（灵动岛也就能继续更新）。
        .onChange(of: scenePhase, initial: true) { _, phase in
            EventLog.shared.add("App 进入\(phase.label)")
            switch phase {
            case .active:
                engine.start()
            case .background:
                // 设置为「离开 App 时不显示悬浮窗」时先收起；收起后的停止采样由悬浮窗的关闭回调处理
                floating.appDidEnterBackground()
                if !floating.isActive {
                    engine.stop()
                }
            default:
                break
            }
        }
    }
}

private enum AppTab: Hashable {
    case status, charging, settings
}

struct RootView: View {
    @Environment(MetricsEngine.self) private var engine
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("autoOpenChargingScreen") private var autoOpenChargingScreen = false
    @State private var tab: AppTab = .status
    @State private var showsChargingScreen = false

    var body: some View {
        TabView(selection: $tab) {
            DashboardView(onOpenChargingScreen: { showsChargingScreen = true },
                          onOpenChargingTab: { tab = .charging })
                .tabItem { Label("状态", systemImage: "gauge.with.dots.needle.67percent") }
                .tag(AppTab.status)
            ChargingTabView(onOpenScreen: { showsChargingScreen = true })
                .tabItem { Label("充电", systemImage: "bolt.fill") }
                .tag(AppTab.charging)
            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
        // 充电大屏放在最外层：首页和充电页都能打开，「插电时自动打开」也不受当前在哪个标签影响
        .fullScreenCover(isPresented: $showsChargingScreen) {
            ChargingScreenView()
                .environment(engine)
        }
        // 设置里打开了「插电时自动打开充电大屏」：App 开着时看到插电就进入
        .onChange(of: ChargeSessionStore.shared.current?.id) { _, newID in
            guard autoOpenChargingScreen, hasCompletedOnboarding, newID != nil,
                  ChargeSessionStore.shared.current?.startObserved == true else { return }
            showsChargingScreen = true
        }
        // 第一次打开时引导添加小组件和开启灵动岛
        .fullScreenCover(isPresented: Binding(get: { !hasCompletedOnboarding }, set: { hasCompletedOnboarding = !$0 })) {
            OnboardingView()
        }
    }
}
