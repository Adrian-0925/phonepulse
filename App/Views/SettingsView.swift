import SwiftUI

struct SettingsView: View {
    @AppStorage(AppSettings.batteryCapacityKey) private var capacityOverride = 0

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("机型", value: DeviceCatalog.displayName)
                    LabeledContent("内置容量", value: DeviceCatalog.current.map { "\($0.batteryMAh) mAh" } ?? "未收录")
                    LabeledContent("自定义容量") {
                        TextField("mAh", value: $capacityOverride, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                } header: {
                    Text("电池")
                } footer: {
                    Text("充电功率是根据电量变化速度和电池容量估算的。电池老化后实际容量会变小，可以填写更准确的值（0 表示使用内置数据）。")
                }

                Section("关于") {
                    LabeledContent("版本", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-")
                }
            }
            .navigationTitle("设置")
        }
    }
}
