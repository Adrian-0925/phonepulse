import SwiftUI
import UIKit

/// 横屏充电大屏：插着电放在桌上看。只在这个页面保持屏幕常亮，离开就恢复。
struct ChargingScreenView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        // 每分钟把内容挪动几个点，减轻长时间显示同一画面的烧屏风险
        TimelineView(.periodic(from: .now, by: 60)) { context in
            ChargingScreenContent()
                .offset(Self.burnInOffset(for: context.date))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 40, height: 40)
                    .background(.white.opacity(0.12), in: Circle())
            }
            .padding(20)
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .preferredColorScheme(.dark)
        .onAppear {
            OrientationLock.set(.landscape)
            UIApplication.shared.isIdleTimerDisabled = true
            EventLog.shared.add("进入充电大屏（屏幕常亮）")
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            OrientationLock.set(.portrait)
            EventLog.shared.add("离开充电大屏（恢复自动锁屏）")
        }
    }

    private static func burnInOffset(for date: Date) -> CGSize {
        let minute = Int(date.timeIntervalSinceReferenceDate / 60)
        return CGSize(width: CGFloat(minute % 5 - 2) * 3, height: CGFloat((minute / 5) % 5 - 2) * 3)
    }
}

private struct ChargingScreenContent: View {
    @Environment(MetricsEngine.self) private var engine

    private var store: ChargeSessionStore { .shared }

    var body: some View {
        let battery = engine.snapshot?.battery
        let session = store.current
        let report = session.flatMap { ChargeAnalyzer.report(for: $0, now: .now) }
        HStack(spacing: 40) {
            batteryColumn(battery)
            VStack(alignment: .leading, spacing: 14) {
                etaRow(battery)
                curve(session: session, battery: battery)
                    .frame(maxHeight: .infinity)
                sessionStats(session: session, report: report)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 56)
        .padding(.vertical, 28)
    }

    // MARK: - 左：电量

    private func batteryColumn(_ battery: BatterySample?) -> some View {
        let state = battery?.state ?? .unknown
        let color = Theme.batteryColor(level: battery?.level, state: state)
        return VStack(alignment: .leading, spacing: 8) {
            Label(stateTitle(state), systemImage: stateIcon(state))
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(battery?.level.map(Format.batteryNumber) ?? "--")
                    .font(Theme.number(150))
                    .foregroundStyle(LinearGradient(colors: [.white, color], startPoint: .top, endPoint: .bottom))
                    .contentTransition(.numericText())
                Text("%")
                    .font(Theme.number(48, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            HStack(spacing: 24) {
                ScreenStat(title: "估算功率", value: battery?.estimatedPowerWatts.map { "≈ \(Format.watts(abs($0)))" } ?? "估算中")
                ScreenStat(title: "充电速度", value: battery?.levelPerHour.map(Format.levelRate) ?? "估算中")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stateTitle(_ state: BatteryState) -> String {
        switch state {
        case .charging: "充电中"
        case .full: "已充满"
        case .unplugged: "未插电"
        case .unknown: "电池状态未知"
        }
    }

    private func stateIcon(_ state: BatteryState) -> String {
        switch state {
        case .charging: "bolt.fill"
        case .full: "checkmark.circle.fill"
        default: "bolt.slash.fill"
        }
    }

    // MARK: - 右：预计充满、曲线、本次统计

    @ViewBuilder
    private func etaRow(_ battery: BatterySample?) -> some View {
        if let battery, battery.state == .charging, let level = battery.level, let rate = battery.levelPerHour,
           let seconds = ChargeForecast.timeToFull(level: level, levelPerHour: rate) {
            let full = Date.now.addingTimeInterval(seconds)
            HStack(alignment: .firstTextBaseline) {
                Text("预计 \(Text(full, style: .time)) 充满")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
                Text("还要 \(Format.duration(seconds))")
                    .font(Theme.number(22, weight: .semibold))
                    .foregroundStyle(Theme.charging)
            }
        } else {
            Text(etaPlaceholder(battery))
                .font(.system(size: 20, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private func etaPlaceholder(_ battery: BatterySample?) -> String {
        switch battery?.state {
        case .full: "已充满，可以拔掉了"
        case .charging: "正在估算充满时间，需要几分钟…"
        case .unplugged: "没有插电。插上电后这里会显示充电进度"
        default: "正在读取电池状态…"
        }
    }

    @ViewBuilder
    private func curve(session: ChargeSession?, battery: BatterySample?) -> some View {
        if let session, session.samples.count >= 2 {
            ChargeCurveChart(samples: samplesWithLivePoint(session, battery: battery))
        } else {
            Text("本次充电曲线会在几分钟后出现")
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.track.opacity(0.4), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    /// 记录里约每分钟一个点，最后补上当前读数，曲线末端跟得上
    private func samplesWithLivePoint(_ session: ChargeSession, battery: BatterySample?) -> [ChargeSample] {
        guard let level = battery?.level, let last = session.samples.last,
              Date.now.timeIntervalSince(last.time) > 5 else { return session.samples }
        return session.samples + [ChargeSample(time: .now, level: level)]
    }

    private func sessionStats(session: ChargeSession?, report: ChargeReport?) -> some View {
        HStack(spacing: 32) {
            ScreenStat(title: "本次已充", value: report.map { String(format: "%+.0f%%", ($0.endLevel - $0.startLevel) * 100) } ?? "--")
            ScreenStat(title: "用时", value: durationText(session: session, report: report))
            ScreenStat(title: "峰值功率", value: report?.peakWatts.map { "≈ \(Format.watts($0))" } ?? "--")
            ScreenStat(title: "数据完整度", value: report.map { Format.percent($0.completeness) } ?? "--")
        }
    }

    private func durationText(session: ChargeSession?, report: ChargeReport?) -> String {
        guard let session, let report else { return "--" }
        // 没看到插电那一刻，真实用时比记录的更长
        return (session.startObserved ? "" : "≥ ") + Format.duration(report.duration)
    }
}

private struct ScreenStat: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
            Text(value)
                .font(Theme.number(24, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }
}
