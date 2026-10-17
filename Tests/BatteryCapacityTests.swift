import XCTest

final class BatteryCapacityTests: XCTestCase {
    func testFullChargeUsesHealth() {
        let capacity = BatteryCapacity(designMAh: 3274, health: 0.87)
        // 3274 × 87% = 2848.38
        XCTAssertEqual(capacity.fullChargeMAh, 2848)
        XCTAssertEqual(capacity.remainingMAh(level: 0.5), 1424)
    }

    func testMissingHealthCountsAsFull() {
        let capacity = BatteryCapacity(designMAh: 3000, health: nil)
        XCTAssertEqual(capacity.fullChargeMAh, 3000)
        XCTAssertEqual(capacity.remainingMAh(level: 0.76), 2280)
    }

    func testValuesAreClamped() {
        let capacity = BatteryCapacity(designMAh: 3000, health: 1.2)
        XCTAssertEqual(capacity.fullChargeMAh, 3000)
        XCTAssertEqual(capacity.remainingMAh(level: 1.5), 3000)
        XCTAssertEqual(capacity.remainingMAh(level: -0.1), 0)
    }
}

final class ChargeForecastTests: XCTestCase {
    func testTimeToFull() throws {
        // 还差 40%，每小时充 60%：40 分钟
        let seconds = try XCTUnwrap(ChargeForecast.timeToFull(level: 0.6, levelPerHour: 0.6))
        XCTAssertEqual(seconds, 40 * 60, accuracy: 1e-6)
    }

    func testNoForecastWhenNotChargingOrFull() {
        XCTAssertNil(ChargeForecast.timeToFull(level: 0.5, levelPerHour: -0.1))
        XCTAssertNil(ChargeForecast.timeToFull(level: 0.5, levelPerHour: 0.005))
        XCTAssertNil(ChargeForecast.timeToFull(level: 1.0, levelPerHour: 0.5))
    }

    func testEstimatorExposesLevelPerHour() throws {
        var estimator = BatteryPowerEstimator()
        for minute in 0...5 {
            estimator.record(level: 0.50 + Double(minute) * 0.01, state: .charging, at: Double(minute) * 60)
        }
        let rate = try XCTUnwrap(estimator.levelPerHour())
        XCTAssertEqual(rate, 0.6, accuracy: 0.001)
        XCTAssertEqual(BatteryPowerEstimator.watts(levelPerHour: rate, capacityMAh: 3000), 6.93, accuracy: 0.01)
    }
}
