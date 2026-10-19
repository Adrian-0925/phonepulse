import XCTest

/// 功率测定的阶段切换：正在采集 → 初步估算 → 较稳定 → 已放缓，以及插拔、暂停后不沿用旧结果
final class PowerMeasurementTests: XCTestCase {
    /// 每秒读一次，真实电量按 perHour 匀速上涨，系统按 step 取整（向下取整，和 iOS 一样只在跨过一档时变化）
    private func simulate(_ estimator: inout BatteryPowerEstimator, from start: Int, to end: Int,
                          startLevel: Double, perHour: Double, step: Double = 0.01, state: BatteryState = .charging) {
        for second in start...end {
            let trueLevel = startLevel + perHour * Double(second - start) / 3600
            let reported = ((trueLevel / step) + 1e-9).rounded(.down) * step
            estimator.record(level: reported, state: state, at: Double(second))
        }
    }

    /// 第一次满足 condition 的秒数
    private func firstSecond(_ estimator: inout BatteryPowerEstimator, until limit: Int, startLevel: Double, perHour: Double,
                             step: Double = 0.01, where condition: (BatteryPowerEstimator) -> Bool) -> Int? {
        for second in 0...limit {
            let trueLevel = startLevel + perHour * Double(second) / 3600
            let reported = ((trueLevel / step) + 1e-9).rounded(.down) * step
            estimator.record(level: reported, state: .charging, at: Double(second))
            if condition(estimator) {
                return second
            }
        }
        return nil
    }

    func testCollectingUntilTwoChanges() throws {
        var estimator = BatteryPowerEstimator()
        estimator.record(level: 0.50, state: .charging, at: 0)
        var status = try XCTUnwrap(estimator.status())
        XCTAssertEqual(status.phase, .collecting)
        XCTAssertEqual(status.changes, 0)

        estimator.record(level: 0.51, state: .charging, at: 20)
        status = try XCTUnwrap(estimator.status())
        XCTAssertEqual(status.phase, .collecting)
        XCTAssertEqual(status.changes, 1)
        XCTAssertNil(estimator.levelPerHour())
    }

    func testPreliminaryThenStable() throws {
        var estimator = BatteryPowerEstimator()
        // 20 W 左右的快充：每 24 秒涨 1%（每小时 150%），第 24、48、72 秒电量变化
        simulate(&estimator, from: 0, to: 75, startLevel: 0.40, perHour: 1.5)
        var status = try XCTUnwrap(estimator.status())
        XCTAssertEqual(status.phase, .preliminary)
        XCTAssertEqual(try XCTUnwrap(estimator.levelPerHour()), 1.5, accuracy: 0.1)

        simulate(&estimator, from: 76, to: 240, startLevel: 0.40 + 1.5 * 76 / 3600, perHour: 1.5)
        status = try XCTUnwrap(estimator.status())
        XCTAssertEqual(status.phase, .stable)
        XCTAssertEqual(try XCTUnwrap(estimator.levelPerHour()), 1.5, accuracy: 0.05)
        // 每秒采样，计时误差很小
        XCTAssertLessThan(try XCTUnwrap(status.timingError), 0.02)
        XCTAssertNotNil(status.lastChangeAt)
    }

    func testFastChargingGivesPreliminaryWithinAMinute() throws {
        // 1% 一档、约 20 W（3300 mAh 每 23 秒涨 1%）：两次变化、跨度 ≥ 36 秒就出初步结果。以前要求跨度 ≥ 60 秒
        var estimator = BatteryPowerEstimator()
        let found: Int? = firstSecond(&estimator, until: 300, startLevel: 0.305, perHour: 1.56) { $0.levelPerHour() != nil }
        let second = try XCTUnwrap(found)
        XCTAssertLessThanOrEqual(second, 60)

        var old = BatteryPowerEstimator()
        old.minimumSpan = 60
        let oldFound: Int? = firstSecond(&old, until: 300, startLevel: 0.305, perHour: 1.56) { $0.levelPerHour() != nil }
        let oldSecond = try XCTUnwrap(oldFound)
        XCTAssertLessThan(second, oldSecond)
    }

    func testTenWattChargingNeedsOnlyOneStepInterval() throws {
        // 约 10 W：每 46 秒涨 1%。一段间隔已超过 36 秒，看到第二次变化就出结果
        var estimator = BatteryPowerEstimator()
        let found: Int? = firstSecond(&estimator, until: 600, startLevel: 0.30, perHour: 0.78) { $0.levelPerHour() != nil }
        XCTAssertLessThanOrEqual(try XCTUnwrap(found), 95)
    }

    func testUnplugStartsNewRound() throws {
        var estimator = BatteryPowerEstimator()
        simulate(&estimator, from: 0, to: 240, startLevel: 0.40, perHour: 1.5)
        XCTAssertEqual(estimator.status()?.phase, .stable)

        estimator.record(level: 0.46, state: .unplugged, at: 241)
        let status = try XCTUnwrap(estimator.status())
        XCTAssertEqual(status.phase, .collecting)
        XCTAssertEqual(status.changes, 0)
        XCTAssertEqual(status.roundStart, Date(timeIntervalSinceReferenceDate: 241))
        XCTAssertNil(estimator.levelPerHour())

        // 再插上：又是新的一轮
        estimator.record(level: 0.46, state: .charging, at: 300)
        XCTAssertEqual(estimator.status()?.roundStart, Date(timeIntervalSinceReferenceDate: 300))
        XCTAssertEqual(estimator.status()?.phase, .collecting)
    }

    func testFullHasNoStatus() {
        var estimator = BatteryPowerEstimator()
        estimator.record(level: 1.0, state: .full, at: 0)
        XCTAssertNil(estimator.status())
    }

    func testShortPauseKeepsEarlierChangesButNotTheFirstReadingBack() throws {
        var estimator = BatteryPowerEstimator()
        estimator.record(level: 0.50, state: .charging, at: 0)
        estimator.record(level: 0.51, state: .charging, at: 30)
        estimator.record(level: 0.52, state: .charging, at: 60)
        estimator.pause(at: 61)
        // 60 秒后回来，电量已经变了：不知道是哪一刻变的，这个读数不能算变化点
        estimator.record(level: 0.55, state: .charging, at: 121)
        XCTAssertEqual(estimator.changePointCount, 2)
        // 下一次真实变化：和暂停前的变化点一起算，速度仍然是每 30 秒 1%
        estimator.record(level: 0.56, state: .charging, at: 150)
        let rate = try XCTUnwrap(estimator.levelPerHour())
        XCTAssertEqual(rate, 0.05 / 120 * 3600, accuracy: 1e-9)
    }

    func testLongPauseStartsNewRound() throws {
        var estimator = BatteryPowerEstimator()
        simulate(&estimator, from: 0, to: 240, startLevel: 0.40, perHour: 1.5)
        estimator.pause(at: 240)
        // 10 分钟后才回来：中间可能拔插过，不沿用上一轮的结果
        estimator.record(level: 0.70, state: .charging, at: 840)
        let status = try XCTUnwrap(estimator.status())
        XCTAssertEqual(status.phase, .collecting)
        XCTAssertEqual(status.changes, 0)
        XCTAssertNil(estimator.levelPerHour())
    }

    func testResumeWithLowerLevelWhileChargingStartsNewRound() throws {
        var estimator = BatteryPowerEstimator()
        estimator.record(level: 0.60, state: .charging, at: 0)
        estimator.record(level: 0.61, state: .charging, at: 30)
        estimator.record(level: 0.62, state: .charging, at: 60)
        estimator.pause(at: 60)
        // 很快回来，但电量变少了：中间拔过电又插上
        estimator.record(level: 0.58, state: .charging, at: 120)
        XCTAssertEqual(estimator.status()?.changes, 0)
        XCTAssertEqual(estimator.changePointCount, 0)
    }

    func testSlowedWhenLevelStopsChanging() throws {
        var estimator = BatteryPowerEstimator()
        // 每 30 秒涨 1%，然后停在 80% 不动（优化充电）
        for step in 0...10 {
            estimator.record(level: 0.70 + Double(step) * 0.01, state: .charging, at: Double(step * 30))
        }
        XCTAssertNotNil(estimator.levelPerHour())
        for second in 301...420 {
            estimator.record(level: 0.80, state: .charging, at: Double(second))
        }
        let status = try XCTUnwrap(estimator.status())
        XCTAssertEqual(status.phase, .slowed)
        // 2 分钟没涨 1%：速度上限 1% ÷ 120 秒 = 30%/h
        XCTAssertEqual(try XCTUnwrap(status.slowedBoundPerHour), 0.30, accuracy: 0.01)
        // 不再沿用之前「每 30 秒 1%」的结果，也就不会算出错误的充满时间
        XCTAssertNil(estimator.levelPerHour())
        XCTAssertNil(estimator.estimatedWatts(capacityMAh: 3000))

        // 又开始涨：恢复给出结果
        estimator.record(level: 0.81, state: .charging, at: 421)
        XCTAssertNotEqual(estimator.status()?.phase, .slowed)
    }

    func testFloatingPointNoiseIsNotAChange() {
        var estimator = BatteryPowerEstimator()
        estimator.record(level: 0.70 + 10 * 0.01, state: .charging, at: 0)
        estimator.record(level: 0.80, state: .charging, at: 1)
        estimator.record(level: Double(Float(0.80)), state: .charging, at: 2)
        XCTAssertEqual(estimator.changePointCount, 0)
        XCTAssertEqual(estimator.status()?.changes, 0)
    }

    func testRecentWindowFollowsSpeedChange() throws {
        var estimator = BatteryPowerEstimator()
        // 前 5 分钟每 20 秒 1%，之后每 40 秒 1%
        var level = 0.30
        var time = 0
        for _ in 0..<15 {
            estimator.record(level: level, state: .charging, at: Double(time))
            level += 0.01
            time += 20
        }
        for _ in 0..<8 {
            estimator.record(level: level, state: .charging, at: Double(time))
            level += 0.01
            time += 40
        }
        // 最近 3 分钟都是每 40 秒 1%（每小时 90%），不被前面的快充拉高
        XCTAssertEqual(try XCTUnwrap(estimator.levelPerHour()), 0.9, accuracy: 0.05)
    }

    func testFivePercentStepsNeedLongerButStillWork() throws {
        var estimator = BatteryPowerEstimator()
        // 5% 一档、每小时 150%：每 2 分钟变一次
        simulate(&estimator, from: 0, to: 400, startLevel: 0.40, perHour: 1.5, step: 0.05)
        let rate = try XCTUnwrap(estimator.levelPerHour())
        XCTAssertEqual(rate, 1.5, accuracy: 0.05)
        XCTAssertEqual(estimator.recentIntervals.count, 2)
    }
}

final class PowerReadoutTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 10_000)

    private func battery(state: BatteryState = .charging, level: Double? = 0.5, watts: Double? = nil, rate: Double? = nil,
                         capacity: Int? = 3000, power: PowerStatus? = nil) -> BatterySample {
        BatterySample(level: level, state: state, isLowPowerMode: false, estimatedPowerWatts: watts,
                      capacityMAh: capacity, levelPerHour: rate, power: power)
    }

    private func status(_ phase: PowerPhase, changes: Int = 3, changedAgo: TimeInterval? = 12, bound: Double? = nil) -> PowerStatus {
        PowerStatus(phase: phase, roundStart: now.addingTimeInterval(-90),
                    lastChangeAt: changedAgo.map { now.addingTimeInterval(-$0) }, changes: changes,
                    timingError: 0.02, slowedBoundPerHour: bound)
    }

    func testCollectingExplainsWhatItWaitsFor() {
        let none = PowerReadout(battery: battery(power: status(.collecting, changes: 0, changedAgo: nil)), now: now)
        XCTAssertEqual(none.status, .collecting)
        XCTAssertEqual(none.label, "正在采集")
        XCTAssertEqual(none.value, "--")
        XCTAssertTrue(none.detail.contains("已采集 1 分钟"), none.detail)

        let one = PowerReadout(battery: battery(power: status(.collecting, changes: 1)), now: now)
        XCTAssertTrue(one.detail.contains("再变 1 次"), one.detail)
        XCTAssertFalse(one.hasResult)
    }

    func testPreliminaryAndStableShowValueAndUpdateTime() {
        let preliminary = PowerReadout(battery: battery(watts: 18.37, rate: 1.6, power: status(.preliminary)), now: now)
        XCTAssertEqual(preliminary.label, "初步估算")
        XCTAssertEqual(preliminary.value, "≈ 18 W")
        XCTAssertEqual(preliminary.title, "充电功率")
        XCTAssertTrue(preliminary.detail.contains("12 秒前更新"), preliminary.detail)
        XCTAssertTrue(preliminary.detail.contains("还会变"), preliminary.detail)

        let stable = PowerReadout(battery: battery(watts: 4.26, rate: 0.37, power: status(.stable, changedAgo: 2)), now: now)
        XCTAssertEqual(stable.label, "较稳定")
        XCTAssertEqual(stable.value, "≈ 4.3 W")
        XCTAssertTrue(stable.detail.contains("刚刚更新"), stable.detail)
        XCTAssertTrue(stable.hasResult)
    }

    func testWithoutCapacityShowsSpeed() {
        let readout = PowerReadout(battery: battery(rate: 0.42, capacity: nil, power: status(.stable)), now: now)
        XCTAssertEqual(readout.title, "充电速度")
        XCTAssertEqual(readout.value, "+42%/h")
        XCTAssertTrue(readout.detail.contains("未收录机型容量"))
    }

    func testDisconnectedFullAndNoData() {
        XCTAssertEqual(PowerReadout(battery: battery(state: .unplugged), now: now, context: .charging).status, .disconnected)
        XCTAssertEqual(PowerReadout(battery: battery(state: .unplugged), now: now, context: .charging).label, "已断开")
        // 电池页面上没插电是在测耗电，不算断开
        XCTAssertEqual(PowerReadout(battery: battery(state: .unplugged, power: status(.collecting, changes: 0)), now: now).status, .collecting)
        XCTAssertEqual(PowerReadout(battery: battery(state: .full), now: now).status, .full)
        XCTAssertEqual(PowerReadout(battery: battery(level: nil), now: now).label, "暂无数据")
        XCTAssertEqual(PowerReadout(battery: battery(state: .unknown), now: now).status, .noData)
    }

    func testSlowedShowsUpperBound() {
        // 上限每小时 30%，3000 mAh：0.3 × 3.0 × 3.85 = 3.465 W
        let readout = PowerReadout(battery: battery(level: 0.80, power: status(.slowed, changedAgo: 180, bound: 0.30)), now: now)
        XCTAssertEqual(readout.status, .slowed)
        XCTAssertEqual(readout.value, "≤ 3.5 W")
        XCTAssertEqual(readout.label, "充电已放缓")
        XCTAssertTrue(readout.detail.contains("3 分钟 没变化"), readout.detail)
        XCTAssertTrue(readout.detail.contains("优化充电"))
    }

    func testDrainingWhilePluggedIn() {
        let readout = PowerReadout(battery: battery(watts: -2.1, rate: -0.18, power: status(.stable)), now: now)
        XCTAssertEqual(readout.title, "净耗电功率")
        XCTAssertEqual(readout.value, "≈ 2.1 W")
        XCTAssertTrue(readout.detail.contains("耗电比充电快"))
    }

    func testWidgetSampleWithoutStatus() {
        // 小组件自己读数时没有测定状态，有速度就当初步结果
        let readout = PowerReadout(battery: battery(watts: 12, rate: 1.0), now: now)
        XCTAssertEqual(readout.status, .preliminary)
        XCTAssertEqual(readout.value, "≈ 12 W")
        XCTAssertEqual(PowerReadout(battery: battery(), now: now).status, .collecting)
    }

    func testStatusSurvivesJSONAndOldSnapshotsDecode() throws {
        var snapshot = MetricsSnapshot.placeholder
        snapshot.battery.power = status(.stable)
        let decoded = try JSONDecoder().decode(MetricsSnapshot.self, from: JSONEncoder().encode(snapshot))
        XCTAssertEqual(decoded.battery.power, snapshot.battery.power)
        // 旧版本存下的快照没有 power 字段
        let old = try JSONDecoder().decode(MetricsSnapshot.self, from: JSONEncoder().encode(MetricsSnapshot.placeholder))
        XCTAssertNil(old.battery.power)
    }
}
