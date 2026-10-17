import XCTest

final class BatteryPowerEstimatorTests: XCTestCase {
    /// 每分钟涨 1%，3000 mAh：0.6 /h × 3.0 Ah × 3.85 V = 6.93 W
    func testChargingOnePercentPerMinute() throws {
        var estimator = BatteryPowerEstimator()
        for minute in 0...5 {
            estimator.record(level: 0.50 + Double(minute) * 0.01, state: .charging, at: Double(minute) * 60)
        }
        let watts = try XCTUnwrap(estimator.estimatedWatts(capacityMAh: 3000))
        XCTAssertEqual(watts, 6.93, accuracy: 0.01)
    }

    /// 电量按 5% 一档报告时，用变化点计算也应该得到同样的结果
    func testFivePercentStepsGiveSameResult() throws {
        var estimator = BatteryPowerEstimator()
        // 每秒采样一次，真实电量每分钟涨 1%，但系统只按 5% 报告
        for second in 0...(15 * 60) {
            let trueLevel = 0.50 + Double(second) / 60 * 0.01
            let reported = (trueLevel / 0.05).rounded(.down) * 0.05
            estimator.record(level: reported, state: .charging, at: Double(second))
        }
        let watts = try XCTUnwrap(estimator.estimatedWatts(capacityMAh: 3000))
        XCTAssertEqual(watts, 6.93, accuracy: 0.2)
    }

    func testNeedsMinimumSpan() {
        var estimator = BatteryPowerEstimator()
        estimator.record(level: 0.50, state: .charging, at: 0)
        estimator.record(level: 0.51, state: .charging, at: 10)
        estimator.record(level: 0.52, state: .charging, at: 40)
        // 变化点只相隔 30 秒，不足 60 秒
        XCTAssertNil(estimator.estimatedWatts(capacityMAh: 3000))
    }

    func testDischargeIsNegative() throws {
        var estimator = BatteryPowerEstimator()
        for minute in 0...10 {
            estimator.record(level: 0.80 - Double(minute) * 0.005, state: .unplugged, at: Double(minute) * 60)
        }
        let watts = try XCTUnwrap(estimator.estimatedWatts(capacityMAh: 3000))
        XCTAssertLessThan(watts, 0)
    }

    func testStateChangeResetsHistory() {
        var estimator = BatteryPowerEstimator()
        for minute in 0...5 {
            estimator.record(level: 0.50 + Double(minute) * 0.01, state: .charging, at: Double(minute) * 60)
        }
        estimator.record(level: 0.55, state: .unplugged, at: 400)
        XCTAssertEqual(estimator.changePointCount, 0)
        XCTAssertNil(estimator.estimatedWatts(capacityMAh: 3000))
    }

    func testOldPointsFallOutOfWindow() {
        var estimator = BatteryPowerEstimator()
        estimator.record(level: 0.50, state: .charging, at: 0)
        estimator.record(level: 0.51, state: .charging, at: 60)
        estimator.record(level: 0.52, state: .charging, at: 120)
        // 20 分钟后才有下一个变化点，前面的都超出 15 分钟窗口
        estimator.record(level: 0.53, state: .charging, at: 120 + 20 * 60)
        XCTAssertEqual(estimator.changePointCount, 1)
        XCTAssertNil(estimator.estimatedWatts(capacityMAh: 3000))
    }

    func testNoEstimateWithoutCapacityOrWhenFull() {
        var estimator = BatteryPowerEstimator()
        for minute in 0...5 {
            estimator.record(level: 0.50 + Double(minute) * 0.01, state: .charging, at: Double(minute) * 60)
        }
        XCTAssertNil(estimator.estimatedWatts(capacityMAh: nil))
        XCTAssertNil(estimator.estimatedWatts(capacityMAh: 0))

        var full = BatteryPowerEstimator()
        full.record(level: 1.0, state: .full, at: 0)
        XCTAssertNil(full.estimatedWatts(capacityMAh: 3000))
    }
}
