import SwiftUI

struct SettingsView: View {
    @State private var showsGuide = false
    @State private var showsControlGuide = false
    @AppStorage("autoOpenChargingScreen") private var autoOpenChargingScreen = false
    @AppStorage(ChargeSessionStore.autoAssignKey) private var autoAssignAccessory = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        showsGuide = true
                    } label: {
                        Label("添加小组件和开启灵动岛", systemImage: "questionmark.circle")
                    }
                    if ControlCenterTip.isSupported {
                        Button {
                            showsControlGuide = true
                        } label: {
                            Label("添加控制中心按钮", systemImage: "switch.2")
                        }
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
                    Toggle("插电时自动打开充电大屏", isOn: $autoOpenChargingScreen)
                    Toggle("新的充电沿用上次的配件组合", isOn: $autoAssignAccessory)
                } header: {
                    Text("充电")
                } footer: {
                    Text("充电记录、充电器对比在「充电」标签页。\n自动打开大屏只在 App 开着时生效，大屏会让屏幕保持常亮，离开后恢复自动锁屏。\n沿用配件：适合总用同一套充电器的人；换了充电器记得在充电页改一下，否则对比会不准。默认关闭，充电时会提供「还是用上次的」一键选择。")
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
            .sheet(isPresented: $showsControlGuide) {
                ControlCenterGuideView()
            }
        }
    }
}
