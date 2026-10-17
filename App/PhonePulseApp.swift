import SwiftUI

@main
struct PhonePulseApp: App {
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
        // 例外：悬浮窗开着时系统允许 App 继续运行，这时不停止采样。
        .onChange(of: scenePhase, initial: true) { _, phase in
            EventLog.shared.add("App 进入\(phase.label)")
            switch phase {
            case .active: engine.start()
            case .background where !floating.isActive: engine.stop()
            default: break
            }
        }
    }
}

struct RootView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("状态", systemImage: "gauge.with.dots.needle.67percent") }
            SpeedTestView()
                .tabItem { Label("测速", systemImage: "speedometer") }
            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape") }
        }
        // 第一次打开时引导添加小组件和开启灵动岛
        .fullScreenCover(isPresented: Binding(get: { !hasCompletedOnboarding }, set: { hasCompletedOnboarding = !$0 })) {
            OnboardingView()
        }
    }
}
