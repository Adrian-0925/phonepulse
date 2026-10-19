import SwiftUI

/// 首次打开时的引导：三步，讲清楚"主角是小组件和灵动岛"以及怎么添加
struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var page = 0

    private let lastPage = 2

    var body: some View {
        VStack(spacing: 20) {
            TabView(selection: $page) {
                GuidePage(
                    icon: "gauge.with.dots.needle.67percent",
                    tint: Theme.battery,
                    title: "看一眼桌面，就知道手机状态",
                    message: "PhonePulse 的主角是桌面小组件和灵动岛。平时不用打开 App，电量、充电、网速、CPU、存储都在桌面上。",
                    steps: [])
                    .tag(0)
                GuidePage(
                    icon: "square.grid.2x2.fill",
                    tint: Theme.network,
                    title: "添加桌面小组件",
                    message: "默认的「概览」已经搭配好了，添加后就能直接看懂。",
                    steps: [
                        "回到桌面，长按空白处直到图标晃动",
                        "点左上角的「编辑」→「添加小组件」（部分系统是「+」）",
                        "搜索 PhonePulse，选一个尺寸添加",
                        "想换内容：长按小组件 →「编辑小组件」→ 选一个预设",
                    ])
                    .tag(1)
                LiveActivityGuidePage()
                    .tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            Button {
                if page < lastPage {
                    withAnimation { page += 1 }
                } else {
                    hasCompletedOnboarding = true
                    dismiss()
                }
            } label: {
                Text(page < lastPage ? "下一步" : "开始使用")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(Theme.battery)
            .foregroundStyle(.black)
            .padding(.horizontal)
            .padding(.bottom)
        }
        .background(Theme.background(.dark).ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}

private struct GuidePage: View {
    let icon: String
    let tint: Color
    let title: String
    let message: String
    let steps: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 52, weight: .bold))
                .foregroundStyle(tint)
            Text(title)
                .font(.system(size: 28, weight: .heavy, design: .rounded))
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
            if !steps.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { item in
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(item.offset + 1)")
                                .font(Theme.number(14))
                                .foregroundStyle(.black)
                                .frame(width: 22, height: 22)
                                .background(tint, in: Circle())
                            Text(item.element)
                                .font(.subheadline)
                        }
                    }
                }
                .padding(.top, 4)
            }
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 28)
    }
}

private struct LiveActivityGuidePage: View {
    @State private var message: String?

    private var service: LiveActivityService { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer()
            Image(systemName: "capsule.fill")
                .font(.system(size: 52, weight: .bold))
                .foregroundStyle(Theme.charging)
            Text("在灵动岛上随时看")
                .font(.system(size: 28, weight: .heavy, design: .rounded))
            Text(DeviceCatalog.current?.hasDynamicIsland == false
                 ? "你的机型没有灵动岛，开启后会显示在锁屏上。插电时显示电量和预计充满时间，平时显示网速。"
                 : "用别的 App 时也能看到电量、充电和网速。插电时自动显示充电信息，收起简洁，长按展开看更多。")
                .foregroundStyle(.secondary)
            Button {
                Task {
                    do {
                        try await service.toggle()
                        message = service.isRunning ? "已开启，回到桌面看看灵动岛吧" : "已关闭"
                    } catch {
                        message = "无法开启：\(error.localizedDescription)"
                    }
                }
            } label: {
                Label(service.isRunning ? "关闭灵动岛" : "现在开启", systemImage: "capsule.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(Theme.charging)
            .controlSize(.large)
            Text(message ?? (ControlCenterTip.isSupported
                             ? "以后也可以在首页、大尺寸小组件或控制中心（设置 → 添加控制中心按钮）开关。App 在前台时实时刷新，其他时候显示最后一次的数据。"
                             : "以后也可以在首页顶部或大尺寸小组件上开关。App 在前台时实时刷新，其他时候显示最后一次的数据。"))
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 28)
    }
}
