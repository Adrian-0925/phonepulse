import SwiftUI

struct SettingsView: View {
    @State private var showsGuide = false
    @AppStorage("autoOpenChargingScreen") private var autoOpenChargingScreen = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        showsGuide = true
                    } label: {
                        Label("添加小组件和开启灵动岛", systemImage: "questionmark.circle")
                    }
                    NavigationLink {
                        BatteryDetailView()
                    } label: {
                        Label("电池健康与容量", systemImage: "battery.100percent")
                    }
                } header: {
                    Text("常用")
                } footer: {
                    Text("在电池页面填写系统设置里的「最大容量」，充电功率和剩余 mAh 会更准。")
                }

                Section {
                    NavigationLink {
                        ChargeHistoryView()
                    } label: {
                        Label("充电记录", systemImage: "list.bullet.rectangle")
                    }
                    Toggle("插电时自动打开充电大屏", isOn: $autoOpenChargingScreen)
                } header: {
                    Text("充电")
                } footer: {
                    Text("只在 App 开着时生效。充电大屏会让屏幕保持常亮，离开大屏后恢复自动锁屏。")
                }

                Section("设备") {
                    LabeledContent("机型", value: DeviceCatalog.displayName)
                    if let model = DeviceCatalog.current {
                        LabeledContent("芯片", value: model.chip)
                        LabeledContent("GPU", value: "\(model.gpuCores) 核（规格）")
                        LabeledContent("设计容量", value: "\(model.batteryMAh) mAh（规格）")
                        LabeledContent("灵动岛", value: model.hasDynamicIsland ? "支持" : "不支持，显示在锁屏")
                    }
                }

                Section {
                    NavigationLink {
                        DiagnosticsView()
                    } label: {
                        Label("真机诊断", systemImage: "stethoscope")
                    }
                } header: {
                    Text("开发者")
                } footer: {
                    Text("查看各项原始读数和运行事件，可复制成报告用于排查问题。")
                }

                Section("关于") {
                    LabeledContent("版本", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-")
                }
            }
            .navigationTitle("设置")
            .sheet(isPresented: $showsGuide) {
                OnboardingView()
            }
        }
    }
}
