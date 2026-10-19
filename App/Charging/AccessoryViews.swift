import SwiftUI

// MARK: - 选择配件组合

/// 给一条充电记录选配件组合：一个菜单，常用的在前，最后是「新建」。首页充电卡片和充电报告共用
struct AccessoryPicker: View {
    let sessionID: UUID
    /// 紧凑样式（首页卡片上一行显示）
    var compact = false

    @State private var showsNewAlert = false
    @State private var newName = ""

    private var store: ChargeSessionStore { .shared }
    private var selected: AccessoryProfile? { store.accessory(store.session(sessionID)?.accessoryID) }

    var body: some View {
        Menu {
            ForEach(store.book.sortedByRecent) { profile in
                Button {
                    store.assign(profile.id, to: sessionID)
                } label: {
                    if profile.id == selected?.id {
                        Label(profile.name, systemImage: "checkmark")
                    } else {
                        Text(profile.name)
                    }
                }
            }
            if selected != nil {
                Button("不指定", role: .destructive) {
                    store.assign(nil, to: sessionID)
                }
            }
            Divider()
            Button {
                newName = ""
                showsNewAlert = true
            } label: {
                Label("新建配件组合…", systemImage: "plus")
            }
        } label: {
            label
        }
        .alert("新建配件组合", isPresented: $showsNewAlert) {
            TextField("例如：床头充电器＋白色线", text: $newName)
            Button("创建并选用") {
                store.createAccessory(named: newName, assigningTo: sessionID)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("给这套充电器和线材起个名字，以后一点就能选。")
        }
    }

    @ViewBuilder
    private var label: some View {
        if compact {
            HStack(spacing: 6) {
                Image(systemName: "cable.connector")
                    .foregroundStyle(Theme.charging)
                Text(selected?.name ?? "选择配件组合")
                    .foregroundStyle(selected == nil ? .secondary : .primary)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
        } else {
            LabeledContent("配件组合") {
                HStack(spacing: 4) {
                    Text(selected?.name ?? "未指定")
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                }
                .foregroundStyle(selected == nil ? .secondary : .primary)
            }
        }
    }
}

/// 正在充电、还没选配件时：一键沿用上次的组合
struct LastAccessorySuggestion: View {
    let sessionID: UUID

    private var store: ChargeSessionStore { .shared }

    var body: some View {
        if store.session(sessionID)?.accessoryID == nil, let last = store.book.lastUsed {
            Button {
                store.assign(last.id, to: sessionID)
            } label: {
                Label("还是用「\(last.name)」", systemImage: "arrow.uturn.backward")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(Theme.charging)
        }
    }
}

// MARK: - 管理配件组合

struct AccessoryListView: View {
    @State private var showsNewAlert = false
    @State private var newName = ""
    @State private var renaming: AccessoryProfile?
    @State private var renameText = ""
    @State private var renameFailed = false

    private var store: ChargeSessionStore { .shared }

    var body: some View {
        List {
            Section {
                if store.book.profiles.isEmpty {
                    Text("还没有配件组合。点右上角「＋」新建，或者在充电记录里直接选「新建配件组合」。")
                        .foregroundStyle(.secondary)
                }
                ForEach(store.book.sortedByRecent) { profile in
                    NavigationLink {
                        AccessorySessionsView(accessoryID: profile.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(profile.name)
                            Text("\(store.sessions(for: profile.id).count) 次记录")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button("删除", role: .destructive) {
                            store.deleteAccessory(profile.id)
                        }
                        Button("改名") {
                            renameText = profile.name
                            renaming = profile
                        }
                        .tint(.gray)
                    }
                }
            } footer: {
                Text("左滑可以改名或删除。删除组合不会删除充电记录，只是改回「未指定」。")
            }

            if store.book.profiles.count >= 2 {
                Section {
                    NavigationLink {
                        AccessoryCompareView()
                    } label: {
                        Label("对比两个组合", systemImage: "chart.bar.xaxis")
                    }
                }
            }
        }
        .navigationTitle("配件组合")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button {
                newName = ""
                showsNewAlert = true
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("新建配件组合")
        }
        .alert("新建配件组合", isPresented: $showsNewAlert) {
            TextField("例如：办公室充电器＋黑色线", text: $newName)
            Button("创建") {
                store.createAccessory(named: newName)
            }
            Button("取消", role: .cancel) {}
        }
        .alert("改名", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("名称", text: $renameText)
            Button("保存") {
                if let renaming {
                    renameFailed = !store.renameAccessory(renaming.id, to: renameText)
                }
                renaming = nil
            }
            Button("取消", role: .cancel) {
                renaming = nil
            }
        }
        .alert("没有改名", isPresented: $renameFailed) {
            Button("好", role: .cancel) {}
        } message: {
            Text("名字不能为空，也不能和已有的组合重名。")
        }
    }
}

/// 某个组合的全部记录
private struct AccessorySessionsView: View {
    let accessoryID: UUID

    private var store: ChargeSessionStore { .shared }

    var body: some View {
        List {
            let sessions = store.sessions(for: accessoryID)
            if sessions.isEmpty {
                Text("还没有关联的充电记录。充电时在首页的充电卡片上选这个组合，或者在充电记录里补选。")
                    .foregroundStyle(.secondary)
            }
            ForEach(sessions) { session in
                NavigationLink {
                    ChargeReportView(sessionID: session.id)
                } label: {
                    ChargeSessionRow(session: session)
                }
            }
        }
        .navigationTitle(store.accessory(accessoryID)?.name ?? "配件组合")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 对比

struct AccessoryCompareView: View {
    @State private var firstID: UUID?
    @State private var secondID: UUID?
    @State private var showsMethod = false

    private var store: ChargeSessionStore { .shared }

    var body: some View {
        let profiles = store.book.sortedByRecent
        List {
            Section {
                Picker("组合 A", selection: $firstID) {
                    ForEach(profiles) { Text($0.name).tag(Optional($0.id)) }
                }
                Picker("组合 B", selection: $secondID) {
                    ForEach(profiles) { Text($0.name).tag(Optional($0.id)) }
                }
            } footer: {
                if profiles.count < 2 {
                    Text("至少需要两个配件组合。先在充电记录里给记录选上组合。")
                }
            }

            if let firstID, let secondID, firstID != secondID {
                let comparison = AccessoryComparison.compare(firstID, secondID, sessions: store.sessions)
                CompareResultSections(comparison: comparison)
            } else if firstID != nil, firstID == secondID {
                Section {
                    Text("请选择两个不同的组合。")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                DisclosureGroup("怎么比较的", isExpanded: $showsMethod) {
                    Text(methodText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("配件对比")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // 默认选最近用过的两个
            if firstID == nil { firstID = profiles.first?.id }
            if secondID == nil { secondID = profiles.dropFirst().first?.id }
        }
    }

    private var methodText: String {
        """
        • 只在两组记录都完整覆盖的同一段电量区间里比较（至少 10 个百分点），优先选 80% 以下，避开系统放慢充电的阶段。
        • 用时取「电量刚涨到区间下限」到「刚涨到上限」的真实时间，只用 App 实际在记录的连续数据；中间断开的记录不参与。
        • 每组取中位数，避免一次异常记录拉偏结果。每组至少 \(AccessoryComparison.conclusiveRuns) 次记录才给结论；差别小于 \(Int(AccessoryComparison.similarThreshold * 100))% 算差不多。
        • 功率 = 速度 × 满电容量 × 3.85V，是估算的电池净充入功率，不是充电器标称瓦数。
        • 边充边用、手机发热（系统会限速）、开着优化充电、电池温度不同，都会让同一套配件快慢不一。想比得准，尽量在相近的电量、放着不用时充。
        """
    }
}

private struct CompareResultSections: View {
    let comparison: AccessoryComparison

    private var store: ChargeSessionStore { .shared }

    var body: some View {
        Section {
            VerdictView(comparison: comparison, nameA: name(comparison.a.accessoryID), nameB: name(comparison.b.accessoryID))
        } header: {
            Text("结论")
        }

        if let range = comparison.range {
            Section {
                CompareRow(title: "参与对比", a: "\(comparison.a.runs.count) 次", b: "\(comparison.b.runs.count) 次")
                CompareRow(title: "\(range.lowerBound)% → \(range.upperBound)% 用时",
                           a: comparison.a.medianDuration.map(Format.duration) ?? "--",
                           b: comparison.b.medianDuration.map(Format.duration) ?? "--")
                CompareRow(title: "电量增长速度",
                           a: comparison.a.medianLevelPerHour.map(Format.levelRate) ?? "--",
                           b: comparison.b.medianLevelPerHour.map(Format.levelRate) ?? "--")
                CompareRow(title: "功率（估算）",
                           a: comparison.a.medianWatts.map { "≈ " + Format.estimatedWatts($0) } ?? "--",
                           b: comparison.b.medianWatts.map { "≈ " + Format.estimatedWatts($0) } ?? "--")
            } header: {
                CompareHeader(title: "同一区间 \(range.lowerBound)% → \(range.upperBound)%", nameA: name(comparison.a.accessoryID), nameB: name(comparison.b.accessoryID))
            } footer: {
                Text(rangeFooter)
            }
        }

        Section {
            CompareRow(title: "记录次数", a: "\(comparison.a.sessionCount) 次", b: "\(comparison.b.sessionCount) 次")
            CompareRow(title: "常见起止电量", a: levelRange(comparison.a), b: levelRange(comparison.b))
            CompareRow(title: "单次充电时长",
                       a: comparison.a.typicalDuration.map(Format.duration) ?? "--",
                       b: comparison.b.typicalDuration.map(Format.duration) ?? "--")
        } header: {
            CompareHeader(title: "全部记录（中位数）", nameA: name(comparison.a.accessoryID), nameB: name(comparison.b.accessoryID))
        } footer: {
            Text("起止电量和时长不同的记录不能直接比快慢，只作参考；快慢以上面同一区间的结果为准。")
        }
    }

    private var rangeFooter: String {
        var notes: [String] = ["功率根据电量变化和满电容量推算，标「≈」的都是估算。"]
        if comparison.hadHeat {
            notes.append("有记录在充电时手机发热（温控偏高），系统可能限速，结果偏慢。")
        }
        if let spread = [comparison.a.spread, comparison.b.spread].compactMap({ $0 }).max(), spread > 0.3 {
            notes.append("同一组里的几次记录快慢相差 \(Int(spread * 100))%，可能有边充边用或发热的情况。")
        }
        return notes.joined(separator: "\n")
    }

    private func name(_ id: UUID) -> String {
        store.accessory(id)?.name ?? "已删除的组合"
    }

    private func levelRange(_ stats: AccessoryStats) -> String {
        guard let start = stats.typicalStartLevel, let end = stats.typicalEndLevel else { return "--" }
        return "\(Format.batteryPercent(start)) → \(Format.batteryPercent(end))"
    }
}

private struct VerdictView: View {
    let comparison: AccessoryComparison
    let nameA: String
    let nameB: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var title: String {
        switch comparison.verdict {
        case .insufficient: "数据不足，继续记录"
        case .preliminary: "初步数据，暂不下结论"
        case .similar: "两组差不多"
        case let .faster(id, difference):
            "「\(id == comparison.a.accessoryID ? nameA : nameB)」快约 \(Int((difference * 100).rounded()))%"
        }
    }

    private var message: String {
        let needed = AccessoryComparison.conclusiveRuns
        switch comparison.verdict {
        case let .insufficient(.noRecords(id)):
            return "「\(id == comparison.a.accessoryID ? nameA : nameB)」还没有关联的充电记录。下次用它充电时，在首页充电卡片上选上它。"
        case .insufficient(.noCommonRange):
            return "两组记录没有重合的电量区间（至少要连续覆盖 10 个百分点，中间 App 不能断开）。试着从相近的电量开始充，并让 App 开着或打开悬浮窗。"
        case .preliminary:
            return "每组至少要 \(needed) 次覆盖同一区间的记录才给结论。现在 A \(comparison.a.runs.count) 次、B \(comparison.b.runs.count) 次，下面的数字先作参考。"
        case let .similar(difference):
            return "同一区间里速度只差 \(Int((difference * 100).rounded()))%，在估算误差和日常波动范围内，可以认为一样快。"
        case .faster:
            return "按同一电量区间的中位数比较。差别较小时，边充边用或发热也可能造成这样的差距。"
        }
    }

    private var icon: String {
        switch comparison.verdict {
        case .insufficient: "hourglass"
        case .preliminary: "chart.bar"
        case .similar: "equal.circle.fill"
        case .faster: "bolt.circle.fill"
        }
    }

    private var tint: Color {
        switch comparison.verdict {
        case .insufficient, .preliminary: .secondary
        case .similar: Theme.network
        case .faster: Theme.charging
        }
    }
}

private struct CompareHeader: View {
    let title: String
    let nameA: String
    let nameB: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
            HStack {
                Spacer()
                Text("A · \(nameA)")
                    .frame(width: 104, alignment: .trailing)
                Text("B · \(nameB)")
                    .frame(width: 104, alignment: .trailing)
            }
            .font(.caption2)
            .lineLimit(1)
            .textCase(nil)
        }
    }
}

private struct CompareRow: View {
    let title: String
    let a: String
    let b: String

    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline)
            Spacer(minLength: 8)
            Text(a)
                .frame(width: 104, alignment: .trailing)
            Text(b)
                .frame(width: 104, alignment: .trailing)
        }
        .font(.subheadline.monospacedDigit())
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}
