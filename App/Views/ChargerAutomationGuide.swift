import SwiftUI

/// 快捷指令自动化的设置指引：插电 / 拔电时各运行一次 PhonePulse。
/// 效果：App 没开时也能记下每次充电的起止，插电时自动开启灵动岛。动作本身见 Platform/Intents.swift
struct ChargerAutomationGuideView: View {
    @Environment(\.dismiss) private var dismiss

    private var store: ChargeSessionStore { .shared }

    private let plugSteps = [
        "打开「快捷指令」App，点底部的「自动化」",
        "点右上角的「＋」（第一次用是「新建自动化」）",
        "往下找到「充电器」，选「已连接」和「立即运行」，点「下一步」",
        "点「新建空白自动化」→「添加操作」，搜索 PhonePulse，选「PhonePulse 已插电」",
    ]

    private let unplugSteps = [
        "再新建一个自动化：「充电器」→「已断开」→「立即运行」",
        "添加操作「PhonePulse 已拔电」",
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    statusRow
                }

                Section {
                    StepList(steps: plugSteps)
                } header: {
                    Text("插电时")
                } footer: {
                    Text("动作里的「同时开启灵动岛」默认打开；关掉就只记录充电，不开灵动岛。")
                }

                Section {
                    StepList(steps: unplugSteps)
                } header: {
                    Text("拔电时")
                } footer: {
                    Text("「同时结束灵动岛」默认打开；想让灵动岛拔电后继续显示网速，就把它关掉。")
                }

                Section {
                    BenefitRow(icon: "list.bullet.rectangle", title: "每次充电都有记录",
                               message: "App 没开也能记下准确的插电、拔电时间和起止电量，算出平均功率。充电过程的曲线仍然只有 App 开着时才有。")
                    BenefitRow(icon: "capsule.fill", title: "插电自动打开灵动岛",
                               message: "显示电量、估算功率和充满倒计时，不用先打开 App。")
                    BenefitRow(icon: "chart.xyaxis.line", title: "充电习惯更准",
                               message: "通常从多少充到多少、常在什么时候充，每次充电都能算进去。")
                } header: {
                    Text("有什么用")
                } footer: {
                    Text("「立即运行」需要 iOS 17 及以上；选「运行前询问」的话，每次插拔电都要点一下确认。")
                }
            }
            .navigationTitle("插电自动记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("完成") { dismiss() }
            }
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        if let date = store.lastAutomationRun {
            Label {
                Text("已生效，上次运行：\(date.formatted(date: .abbreviated, time: .shortened))")
            } icon: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.battery)
            }
        } else {
            Label {
                Text("还没运行过。按下面的步骤设置好后，插一次电试试。")
            } icon: {
                Image(systemName: "circle.dashed")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct StepList: View {
    let steps: [String]

    var body: some View {
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
    }
}

private struct BenefitRow: View {
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
