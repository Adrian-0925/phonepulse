import SwiftUI

/// 控制中心按钮的添加指引（iOS 18 起）
struct ControlCenterGuideView: View {
    @Environment(\.dismiss) private var dismiss

    private let steps = [
        "从屏幕右上角往下滑，打开控制中心",
        "点左上角的「＋」（或长按空白处）进入编辑",
        "点底部「添加控制」，搜索 PhonePulse",
        "选「灵动岛开关」「刷新手机状态」「切换灵动岛内容」，拖到顺手的位置",
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Array(steps.enumerated()), id: \.offset) { item in
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(item.offset + 1)")
                                .font(Theme.number(14))
                                .foregroundStyle(.black)
                                .frame(width: 22, height: 22)
                                .background(Theme.charging, in: Circle())
                            Text(item.element)
                                .font(.subheadline)
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Text("添加到控制中心")
                } footer: {
                    Text("同样的按钮也能放到锁屏底部（编辑锁屏 → 点左下 / 右下的按钮位置），或绑定到操作按钮（iPhone 15 Pro 及以后：设置 → 操作按钮 → 控制）。")
                }

                Section {
                    GuideRow(icon: "capsule.fill", title: "灵动岛开关", message: "开启或结束灵动岛。点完灵动岛会出现或消失。")
                    GuideRow(icon: "arrow.clockwise", title: "刷新手机状态", message: "现场读一次数据，更新灵动岛和小组件。灵动岛状态会变成「手动刷新」和当前时间。")
                    GuideRow(icon: "arrow.left.arrow.right", title: "切换灵动岛内容", message: "自动 → 电池 → 网速 → 性能。灵动岛没开时会先开启。")
                } header: {
                    Text("三个按钮")
                } footer: {
                    Text(SharedStore.isAppGroupAvailable
                         ? "按钮名称会显示灵动岛当前状态（如「结束灵动岛」「灵动岛：电池」）。"
                         : "当前安装方式不支持 App 和控制中心共享数据，按钮只能显示通用名称（如「开关灵动岛」），但操作照样有效。")
                }
            }
            .navigationTitle("控制中心")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("完成") { dismiss() }
            }
        }
    }
}

private struct GuideRow: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.charging)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

/// 首页灵动岛卡片里的一次性提示：iOS 18 起可以把按钮加到控制中心
struct ControlCenterTip: View {
    @AppStorage("dismissedControlCenterTip") private var dismissed = false
    @State private var showsGuide = false

    /// 控制中心按钮 iOS 18 起才有
    static var isSupported: Bool {
        ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 18, minorVersion: 0, patchVersion: 0))
    }

    var body: some View {
        if Self.isSupported, !dismissed {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "switch.2")
                    .foregroundStyle(Theme.charging)
                VStack(alignment: .leading, spacing: 4) {
                    Text("不打开 App 也能开关灵动岛")
                        .font(.subheadline.weight(.semibold))
                    Text("把「灵动岛开关」「刷新」「切换内容」加到控制中心。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("看看怎么加") {
                        showsGuide = true
                    }
                    .font(.caption.weight(.semibold))
                }
                Spacer(minLength: 0)
                Button {
                    dismissed = true
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("不再提示")
            }
            .padding(10)
            .background(Theme.charging.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .sheet(isPresented: $showsGuide) {
                ControlCenterGuideView()
            }
        }
    }
}
