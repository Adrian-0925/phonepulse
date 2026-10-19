import Foundation

/// 把电池采样整理成界面上统一的「功率测定」显示。App 首页、电池详情、充电大屏、灵动岛共用，
/// 保证各处对「正在采集 / 初步估算 / 较稳定 / 已放缓 / 已断开 / 暂无数据」的说法一致。
struct PowerReadout: Equatable {
    enum Status: Equatable {
        /// 读不到电池数据（模拟器、系统未提供）
        case noData
        /// 充电页面上：充电器已拔出
        case disconnected
        case full
        case collecting
        case preliminary
        case stable
        case slowed
    }

    /// 在哪种页面上显示
    enum Context {
        /// 充电相关页面：没插电就是「已断开」
        case charging
        /// 电池页面：没插电时测耗电
        case battery
    }

    var status: Status
    /// 主数值，如「≈ 18 W」「+42%/h」「≤ 1 W」；没有结果时为「--」
    var value: String
    /// 主数值是什么：充电功率 / 耗电功率 / 充电速度…
    var title: String
    /// 状态标签
    var label: String
    /// 补充说明：结果更新时间，或者还要等什么
    var detail: String

    /// 有可用的数值结果
    var hasResult: Bool { status == .preliminary || status == .stable }

    init(status: Status, value: String, title: String, label: String, detail: String) {
        self.status = status
        self.value = value
        self.title = title
        self.label = label
        self.detail = detail
    }

    init(battery: BatterySample, now: Date, context: Context = .battery) {
        guard battery.level != nil, battery.state != .unknown else {
            self.init(status: .noData, value: "--", title: "充电功率", label: "暂无数据", detail: "读不到电池数据（模拟器或系统未提供）")
            return
        }
        if battery.state == .full {
            self.init(status: .full, value: "已充满", title: "充电", label: "已充满", detail: "充满后不再测定充电功率")
            return
        }
        if battery.state == .unplugged, context == .charging {
            self.init(status: .disconnected, value: "--", title: "充电功率", label: "已断开", detail: "充电器已拔出，插上后重新开始测定")
            return
        }

        let charging = battery.state == .charging
        let hasCapacity = (battery.capacityMAh ?? 0) > 0
        let rate = battery.levelPerHour
        let title: String
        if !hasCapacity {
            title = charging ? "充电速度" : "耗电速度"
        } else if charging, let rate, rate < 0 {
            title = "净耗电功率"
        } else {
            title = charging ? "充电功率" : "耗电功率"
        }

        // 小组件自己读数时没有测定状态：有速度就当初步结果
        let status = battery.power
        let phase = status?.phase ?? (rate == nil ? .collecting : .preliminary)
        switch phase {
        case .collecting:
            self.init(status: .collecting, value: "--", title: title, label: "正在采集",
                      detail: Self.collectingDetail(status, now: now))
        case .preliminary, .stable:
            var value = "--"
            if let watts = battery.estimatedPowerWatts {
                value = "≈ " + Format.estimatedWatts(watts)
            } else if let rate {
                value = Format.levelRate(rate)
            }
            var parts: [String] = []
            if let changed = status?.lastChangeAt {
                parts.append("\(Format.ago(now.timeIntervalSince(changed)))更新")
            }
            if phase == .preliminary {
                parts.append("之后还会变")
            }
            if charging, let rate, rate < 0 {
                parts.append("耗电比充电快")
            }
            if !hasCapacity {
                parts.append("未收录机型容量，只显示速度")
            }
            self.init(status: phase == .stable ? .stable : .preliminary, value: value, title: title,
                      label: phase == .stable ? "较稳定" : "初步估算",
                      detail: parts.joined(separator: " · "))
        case .slowed:
            var value = "--"
            if let bound = status?.slowedBoundPerHour {
                if let capacity = battery.capacityMAh, capacity > 0 {
                    value = "≤ " + Format.estimatedWatts(BatteryPowerEstimator.watts(levelPerHour: bound, capacityMAh: capacity))
                } else {
                    value = String(format: "≤ %.0f%%/h", (bound * 100).rounded(.up))
                }
            }
            var detail = "电量暂时没有变化"
            if let changed = status?.lastChangeAt {
                detail = "电量 \(Format.elapsed(now.timeIntervalSince(changed))) 没变化"
            }
            if charging, let level = battery.level, level >= 0.78 {
                detail += "，可能是优化充电"
            }
            self.init(status: .slowed, value: value, title: title, label: charging ? "充电已放缓" : "耗电很慢", detail: detail)
        }
    }

    private static func collectingDetail(_ status: PowerStatus?, now: Date) -> String {
        guard let status else { return "等待电量变化" }
        switch status.changes {
        case 0:
            return "等待电量第一次变化 · 已采集 \(Format.elapsed(now.timeIntervalSince(status.roundStart)))"
        case 1:
            return "已看到 1 次电量变化，再变 1 次给出初步结果"
        default:
            return "已看到 \(status.changes) 次电量变化，马上给出结果"
        }
    }
}
