import SwiftUI

/// 「充电」标签页：充电时看这一次的测定，平时看上次充电、和平时比、充电习惯，以及记录和对比的入口。
/// 充电相关的功能集中在这里，不插电时也看得到。
struct ChargingTabView: View {
    private let onOpenScreen: () -> Void

    private var store: ChargeSessionStore { .shared }

    init(onOpenScreen: @escaping () -> Void) {
        self.onOpenScreen = onOpenScreen
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    // 读每秒采样的部分单独放一个视图，下面的统计不用跟着每秒重算
                    CurrentChargeSection(onOpenScreen: onOpenScreen)
                    AutomationTipCard()
                    if let last = store.sessions.first {
                        LastChargeCard(session: last)
                        HabitsCard(sessions: store.sessions)
                    } else if store.current == nil {
                        ChargingEmptyCard()
                    }
                    RecordsCard()
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("充电")
        }
    }
}

// MARK: - 本次充电

private struct CurrentChargeSection: View {
    @Environment(MetricsEngine.self) private var engine
    let onOpenScreen: () -> Void

    var body: some View {
        if let battery = engine.snapshot?.battery, battery.state.isPluggedIn {
            CurrentChargeCard(battery: battery, onOpenScreen: onOpenScreen)
        }
    }
}

private struct CurrentChargeCard: View {
    let battery: BatterySample
    let onOpenScreen: () -> Void

    private var store: ChargeSessionStore { .shared }

    var body: some View {
        let readout = PowerReadout(battery: battery, now: .now, context: .charging)
        MetricCard(title: battery.state == .full ? "已充满" : "本次充电", systemImage: "bolt.fill", tint: Theme.charging) {
            HStack(alignment: .firstTextBaseline) {
                Text(battery.level.map(Format.batteryPercent) ?? "--")
                    .font(Theme.number(44))
                    .contentTransition(.numericText())
                Spacer()
                if battery.state != .full {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(readout.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(readout.value)
                            .font(.title2.monospacedDigit().weight(.semibold))
                            .contentTransition(.numericText())
                    }
                }
            }
            if battery.state != .full {
                HStack(spacing: 6) {
                    PowerStatusBadge(readout: readout)
                    Text(readout.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            if let session = store.current {
                sessionDetails(session)
            }
            HStack(spacing: 10) {
                Button(action: onOpenScreen) {
                    Label("充电大屏", systemImage: "rectangle.landscape.rotate")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.charging)
                .foregroundStyle(.black)
                if let session = store.current {
                    NavigationLink {
                        ChargeReportView(sessionID: session.id)
                    } label: {
                        Label("本次报告", systemImage: "doc.text.magnifyingglass")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    @ViewBuilder
    private func sessionDetails(_ session: ChargeSession) -> some View {
        if session.samples.count >= 2 {
            ChargeCurveChart(samples: session.samples, tint: Theme.storage)
                .frame(height: 140)
        } else {
            Text("充电曲线几分钟后出现。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        SpeedVersusUsualView(session: session, history: store.sessions, isOngoing: true)
        HStack(spacing: 8) {
            AccessoryPicker(sessionID: session.id, compact: true)
            Spacer(minLength: 0)
            LastAccessorySuggestion(sessionID: session.id)
        }
    }
}

// MARK: - 和平时比

/// 一句结论：这次比平时快还是慢，慢的话可能是什么原因
struct SpeedVersusUsualView: View {
    let session: ChargeSession
    let history: [ChargeSession]
    /// 正在充电时数据还不够就不显示，免得刚插电就看到一堆说明
    var isOngoing = false

    private struct Content {
        var icon: String
        var tint: Color
        var title: String
        var detail: String
    }

    var body: some View {
        if let content = makeContent(ChargeInsights.speedVersusUsual(session, history: history)) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: content.icon)
                    .font(.title3)
                    .foregroundStyle(content.tint)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(content.title)
                        .font(.subheadline.weight(.semibold))
                    if !content.detail.isEmpty {
                        Text(content.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(content.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func makeContent(_ result: SpeedVersusUsual) -> Content? {
        var timing = ""
        if let range = result.range, let duration = result.duration, let usual = result.usualDuration {
            timing = "\(range.lowerBound)% → \(range.upperBound)% 这次用了 \(Format.duration(duration))，平时约 \(Format.duration(usual))"
        }
        switch result.verdict {
        case let .faster(by: value):
            return Content(icon: "hare.fill", tint: Theme.battery, title: "比平时快 \(Self.percentText(value))", detail: timing)
        case let .slower(by: value):
            let detail = [timing, slowReason].filter { !$0.isEmpty }.joined(separator: "\n")
            return Content(icon: "tortoise.fill", tint: Theme.storage, title: "比平时慢 \(Self.percentText(value))", detail: detail)
        case .similar:
            return Content(icon: "equal.circle.fill", tint: Theme.network, title: "和平时差不多", detail: timing)
        case .insufficient:
            if isOngoing { return nil }
            let needed = max(ChargeInsights.baselineRuns - result.baselineCount, 1)
            return Content(icon: "hourglass", tint: .secondary, title: "还不能和平时比",
                           detail: "再有 \(needed) 次从相近电量开始、App 开着的充电，就能看出这次比平时快还是慢。")
        }
    }

    private var slowReason: String {
        if let thermal = session.peakThermal, thermal.severity >= 1 {
            return "充电时手机发热（温控\(thermal.label)），系统会主动放慢充电。"
        }
        if session.accessoryID == nil {
            return "可能是换了充电器或线材，或者边充边用。给充电选上配件组合，就能对比是哪一套慢。"
        }
        return "可能是边充边用，或者充电器、线材接触不良。"
    }

    private static func percentText(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}

// MARK: - 上次充电

private struct LastChargeCard: View {
    let session: ChargeSession

    private var store: ChargeSessionStore { .shared }

    var body: some View {
        let report = ChargeAnalyzer.report(for: session, now: .now)
        MetricCard(title: "上次充电", systemImage: "clock.arrow.circlepath", tint: Theme.storage) {
            NavigationLink {
                ChargeReportView(sessionID: session.id)
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        MetricValue(text: rangeText(report))
                        Spacer()
                        Text(session.startDate.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    Text(summaryText(report))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if session.samples.count >= 2 {
                        ChargeCurveChart(samples: session.samples, tint: Theme.storage, showsAxes: false)
                            .frame(height: 48)
                    }
                    flags(report)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            SpeedVersusUsualView(session: session, history: store.sessions)
        }
    }

    private func rangeText(_ report: ChargeReport?) -> String {
        guard let report else { return "--" }
        return "\(Format.batteryPercent(report.startLevel)) → \(Format.batteryPercent(report.endLevel))"
    }

    private func summaryText(_ report: ChargeReport?) -> String {
        guard let report else { return "数据不足" }
        var parts: [String] = [(session.startObserved ? "" : "≥ ") + Format.duration(report.duration)]
        if let watts = report.averageWatts {
            parts.append("平均 ≈ \(Format.estimatedWatts(watts))")
        }
        if let accessory = store.accessory(session.accessoryID) {
            parts.append(accessory.name)
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func flags(_ report: ChargeReport?) -> some View {
        let tags = flagTexts(report)
        if !tags.isEmpty {
            HStack(spacing: 6) {
                ForEach(tags, id: \.self) { tag in
                    Text(tag)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.caution)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.caution.opacity(0.15), in: Capsule())
                }
            }
        }
    }

    private func flagTexts(_ report: ChargeReport?) -> [String] {
        var tags: [String] = []
        if report?.optimizedCharging == .suspected {
            tags.append("疑似优化充电")
        }
        if let thermal = session.peakThermal, thermal.severity >= 1 {
            tags.append("充电时发热")
        }
        if let completeness = report?.completeness, completeness < 0.8 {
            // 只有快捷指令记下的插电、拔电两个点：起止和平均是准的，只是没有过程
            tags.append(completeness < 0.05 && session.startObserved && session.endObserved
                        ? "只有起止数据" : "完整度 \(Format.percent(completeness))")
        }
        return tags
    }
}

// MARK: - 插电自动记录

/// 还没设置快捷指令自动化时的提示（可以关掉）
private struct AutomationTipCard: View {
    @AppStorage("dismissedChargerAutomationTip") private var dismissed = false
    @State private var showsGuide = false

    private var store: ChargeSessionStore { .shared }

    var body: some View {
        if store.lastAutomationRun == nil, !dismissed {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "wand.and.stars")
                    .foregroundStyle(Theme.charging)
                VStack(alignment: .leading, spacing: 4) {
                    Text("App 没开也能记录每次充电")
                        .font(.subheadline.weight(.semibold))
                    Text("在「快捷指令」里设两个自动化，插电、拔电时各运行一次 PhonePulse：充电记录有准确的起止时间，插电还会自动打开灵动岛。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("看看怎么设置") {
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
            .padding(12)
            .background(Theme.charging.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .sheet(isPresented: $showsGuide) {
                ChargerAutomationGuideView()
            }
        }
    }
}

// MARK: - 充电习惯

private struct HabitsCard: View {
    let sessions: [ChargeSession]

    var body: some View {
        let habits = ChargeInsights.habits(sessions, calendar: .current)
        let recent = ChargeInsights.recent(sessions, now: .now)
        MetricCard(title: "充电习惯", systemImage: "chart.xyaxis.line", tint: Theme.battery) {
            if let habits {
                habitRows(habits)
            } else {
                teaser
            }
            if recent.count > 0 {
                recentRows(recent, habits: habits)
            }
        }
    }

    private var teaser: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("再记录 \(ChargeInsights.habitMinimum - sessions.count) 次充电，这里会总结你通常从多少充到多少、常在什么时候充。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ProgressView(value: Double(sessions.count), total: Double(ChargeInsights.habitMinimum))
                .tint(Theme.battery)
            Text("已记录 \(sessions.count) / \(ChargeInsights.habitMinimum) 次")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func habitRows(_ habits: ChargeHabits) -> some View {
        if let start = habits.typicalStartLevel, let end = habits.typicalEndLevel {
            InsightRow(icon: "battery.50percent", title: "通常从 \(Format.batteryPercent(start)) 充到 \(Format.batteryPercent(end))",
                       detail: habits.typicalDuration.map { "一次约 \(Format.duration($0))，按 \(habits.sessionCount) 次记录的中位数" })
        }
        if let period = habits.commonStartPeriod {
            InsightRow(icon: period.isNight ? "moon.fill" : "clock", title: "常在\(period.label)开始充电",
                       detail: "看到插电时间的 \(habits.observedStartCount) 次里有 \(habits.commonStartCount) 次")
        }
    }

    @ViewBuilder
    private func recentRows(_ recent: RecentCharging, habits: ChargeHabits?) -> some View {
        InsightRow(icon: "calendar", title: "近 \(recent.days) 天充了 \(recent.count) 次",
                   detail: "App 记录到共充入 \(Format.percent(recent.totalGained))，约 \(String(format: "%.1f", recent.totalGained)) 次满电")
        if let tip = fullChargeTip(recent, habits: habits) {
            InsightRow(icon: "lightbulb.fill", tint: Theme.caution, title: "电池保养", detail: tip)
        }
        if recent.optimizedCount > 0 {
            InsightRow(icon: "pause.circle.fill", tint: Theme.network, title: "有 \(recent.optimizedCount) 次在 80% 左右明显放慢",
                       detail: "这是系统的优化充电在保护电池，不是充电器坏了。")
        }
        if recent.heatCount > 0 {
            InsightRow(icon: "thermometer.medium", tint: Theme.storage, title: "有 \(recent.heatCount) 次充电时手机发热",
                       detail: "发热时系统会放慢充电。尽量别边充边玩大型游戏，也别压在被子、枕头下充。")
        }
    }

    /// 经常充满（尤其夜里一插一整晚）时，提醒打开系统的优化充电
    private func fullChargeTip(_ recent: RecentCharging, habits: ChargeHabits?) -> String? {
        guard recent.count >= 3, recent.reachedFullCount * 2 >= recent.count else { return nil }
        let advice = "可以在系统「设置 → 电池」里打开优化充电或充电上限，减缓电池老化。"
        if habits?.commonStartPeriod?.isNight == true {
            return "你常在夜里充电，最近 \(recent.count) 次里有 \(recent.reachedFullCount) 次充到 100%，一整晚停在满电对电池不太友好。" + advice
        }
        return "最近 \(recent.count) 次里有 \(recent.reachedFullCount) 次充到 100%。" + advice
    }
}

private struct InsightRow: View {
    let icon: String
    var tint: Color = Theme.battery
    let title: String
    var detail: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - 还没有记录

private struct ChargingEmptyCard: View {
    var body: some View {
        MetricCard(title: "还没有充电记录", systemImage: "bolt.fill", tint: Theme.charging) {
            Text("插上电并打开 App，就会自动记录这次充电。充过之后，这里会出现：")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            InsightRow(icon: "chart.xyaxis.line", tint: Theme.charging, title: "充电报告",
                       detail: "用了多久、平均和峰值功率（估算）、有没有进入优化充电")
            InsightRow(icon: "hare.fill", tint: Theme.charging, title: "和平时比",
                       detail: "这次比平时快还是慢，慢的话可能是什么原因")
            InsightRow(icon: "chart.bar.xaxis", tint: Theme.charging, title: "充电器／线材对比",
                       detail: "给充电器起个名字，比较哪一套更快")
            InsightRow(icon: "rectangle.landscape.rotate", tint: Theme.charging, title: "充电大屏",
                       detail: "插电时横屏放在桌上看，屏幕常亮")
        }
    }
}

// MARK: - 记录与对比

private struct RecordsCard: View {
    @State private var showsAutomationGuide = false

    private var store: ChargeSessionStore { .shared }

    var body: some View {
        MetricCard(title: "记录与对比", systemImage: "list.bullet.rectangle", tint: Theme.network) {
            NavigationLink {
                ChargeHistoryView()
            } label: {
                LinkRow(icon: "list.bullet.rectangle", title: "充电记录", value: "\(store.sessions.count) 条")
            }
            Divider()
            Button {
                showsAutomationGuide = true
            } label: {
                LinkRow(icon: "wand.and.stars", title: "插电自动记录", detail: automationStatus)
            }
            Divider()
            NavigationLink {
                AccessoryCompareView()
            } label: {
                LinkRow(icon: "chart.bar.xaxis", title: "充电器／线材对比", detail: compareSummary)
            }
            Divider()
            NavigationLink {
                AccessoryListView()
            } label: {
                LinkRow(icon: "cable.connector", title: "管理配件组合", value: "\(store.book.profiles.count) 个")
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showsAutomationGuide) {
            ChargerAutomationGuideView()
        }
    }

    private var automationStatus: String {
        guard let date = store.lastAutomationRun else { return "未设置：用快捷指令让 App 没开时也记下每次充电" }
        return "已生效 · 上次运行 \(Format.ago(Date.now.timeIntervalSince(date)))"
    }

    /// 最近用过的两个组合的对比结论，一行说完
    private var compareSummary: String {
        let profiles = store.book.sortedByRecent
        guard profiles.count >= 2 else { return "给每次充电选上充电器和线材，就能比较哪一套更快" }
        let first = profiles[0]
        let second = profiles[1]
        let comparison = AccessoryComparison.compare(first.id, second.id, sessions: store.sessions)
        switch comparison.verdict {
        case let .faster(id, difference):
            return "「\(id == first.id ? first.name : second.name)」快约 \(Int((difference * 100).rounded()))%"
        case .similar:
            return "「\(first.name)」和「\(second.name)」差不多"
        case .preliminary:
            return "初步数据，每组再充几次就能下结论"
        case .insufficient:
            return "数据不足，继续记录"
        }
    }
}

private struct LinkRow: View {
    let icon: String
    let title: String
    var value: String?
    var detail: String?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.network)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            if let value {
                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}
