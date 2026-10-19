import SwiftUI

/// 充电记录列表
struct ChargeHistoryView: View {
    private var store: ChargeSessionStore { .shared }

    var body: some View {
        List {
            if let current = store.current {
                Section("正在充电") {
                    NavigationLink {
                        ChargeReportView(sessionID: current.id)
                    } label: {
                        ChargeSessionRow(session: current)
                    }
                }
            }
            Section {
                if store.sessions.isEmpty {
                    Text("还没有充电记录。插上电并打开 App，就会开始记录。")
                        .foregroundStyle(.secondary)
                }
                ForEach(store.sessions) { session in
                    NavigationLink {
                        ChargeReportView(sessionID: session.id)
                    } label: {
                        ChargeSessionRow(session: session)
                    }
                }
                .onDelete { offsets in
                    let targets = offsets.map { store.sessions[$0] }
                    for session in targets {
                        store.delete(session)
                    }
                }
            } header: {
                Text("历史")
            } footer: {
                Text("功率都是根据电量变化估算的。App 没运行的时间没有数据，「完整度」越高，报告越可信。")
            }
        }
        .navigationTitle("充电记录")
    }
}

private struct ChargeSessionRow: View {
    let session: ChargeSession

    var body: some View {
        let report = ChargeAnalyzer.report(for: session, now: .now)
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(session.startDate.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                CompletenessBadge(value: report?.completeness ?? 0)
            }
            HStack(spacing: 12) {
                Text(levelRangeText(report))
                    .monospacedDigit()
                Text(report.map { Format.duration($0.duration) } ?? "--")
                if let watts = report?.averageWatts {
                    Text("平均 ≈ \(Format.watts(watts))")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if report?.optimizedCharging == .suspected {
                Text("疑似优化充电")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.caution)
            }
        }
        .padding(.vertical, 2)
    }
}

/// 单次充电报告
struct ChargeReportView: View {
    let sessionID: UUID

    private var store: ChargeSessionStore { .shared }

    /// 正在充电的那次会随采样更新，所以每次都从存储里取最新的
    private var session: ChargeSession? {
        if let current = store.current, current.id == sessionID {
            return current
        }
        return store.sessions.first { $0.id == sessionID }
    }

    var body: some View {
        if let session, let report = ChargeAnalyzer.report(for: session, now: .now) {
            List {
                Section {
                    ChargeCurveChart(samples: session.samples, tint: Theme.storage)
                        .frame(height: 220)
                        .padding(.vertical, 8)
                } footer: {
                    Text("曲线断开的地方表示 App 没在运行、没有数据。虚线是 80%，系统的优化充电常在这里放慢。")
                }

                Section("概况") {
                    LabeledContent("电量", value: levelRangeText(report))
                    LabeledContent("用时", value: (session.startObserved ? "" : "≥ ") + Format.duration(report.duration))
                    LabeledContent("开始", value: startText(session))
                    LabeledContent("结束", value: endText(session))
                }

                Section {
                    LabeledContent("平均速度", value: report.levelPerHour.map(Format.levelRate) ?? "数据不足")
                    LabeledContent("平均功率", value: report.averageWatts.map { "≈ \(Format.watts($0))" } ?? "数据不足")
                    LabeledContent("峰值功率", value: report.peakWatts.map { "≈ \(Format.watts($0))" } ?? "数据不足")
                } header: {
                    Text("速度与功率（估算）")
                } footer: {
                    Text("根据电量变化和电池满电容量推算，是电池实际充入的功率，不等于充电头的标称瓦数。峰值按任意连续 10 分钟里最快的一段计算。")
                }

                Section {
                    LabeledContent("数据完整度") {
                        CompletenessBadge(value: report.completeness)
                    }
                    LabeledContent("优化充电", value: optimizedText(report.optimizedCharging))
                } header: {
                    Text("可信度")
                } footer: {
                    Text("完整度：这次充电的时间里，有多少比例 App 正在记录。App 关闭期间没有数据（免费安装方式读不到小组件记录的电量点）。\n优化充电：iOS 会根据你的作息在 80% 左右暂停充电，到快要用手机时再充满。这里根据曲线推测，可能误判。")
                }
            }
            .navigationTitle(session.isOngoing ? "本次充电" : session.startDate.formatted(date: .abbreviated, time: .omitted))
            .navigationBarTitleDisplayMode(.inline)
        } else {
            ContentUnavailableView("记录不存在", systemImage: "bolt.slash", description: Text("这条充电记录可能已被删除。"))
        }
    }

    private func startText(_ session: ChargeSession) -> String {
        let time = session.startDate.formatted(date: .omitted, time: .shortened)
        return session.startObserved ? time : "\(time) 之前（插电时 App 没在运行）"
    }

    private func endText(_ session: ChargeSession) -> String {
        guard let end = session.endDate else { return "还在充电" }
        let time = end.formatted(date: .omitted, time: .shortened)
        return session.endObserved ? time : "约 \(time)（之后没有数据）"
    }

    private func optimizedText(_ status: OptimizedChargingStatus) -> String {
        switch status {
        case .suspected: "疑似（80% 左右明显放慢）"
        case .notDetected: "未发现"
        case .insufficientData: "数据不足"
        }
    }
}

private struct CompletenessBadge: View {
    let value: Double

    var body: some View {
        Text("完整度 \(Format.percent(value))")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
    }

    private var color: Color {
        if value >= 0.8 { return Theme.battery }
        if value >= 0.4 { return Theme.caution }
        return .gray
    }
}

private func levelRangeText(_ report: ChargeReport?) -> String {
    guard let report else { return "--" }
    return "\(Format.batteryPercent(report.startLevel)) → \(Format.batteryPercent(report.endLevel))"
}
