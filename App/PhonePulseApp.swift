import SwiftUI

@main
struct PhonePulseApp: App {
    @State private var engine = MetricsEngine()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(engine)
        }
        // iOS 不允许 App 在后台持续运行，所以只在前台采样，退到后台时保存快照给小组件
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .active: engine.start()
            case .background: engine.stop()
            default: break
            }
        }
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("状态", systemImage: "gauge.with.dots.needle.67percent") }
            SpeedTestView()
                .tabItem { Label("测速", systemImage: "speedometer") }
            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape") }
        }
    }
}
