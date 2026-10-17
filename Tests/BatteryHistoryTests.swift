import XCTest

final class BatteryHistoryTests: XCTestCase {
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func point(minutes: Double, level: Double, charging: Bool = false) -> BatteryPoint {
        BatteryPoint(time: start.addingTimeInterval(minutes * 60), level: level, isCharging: charging)
    }

    func testPointsTooCloseReplaceTheLastOne() {
        var history = BatteryHistory()
        history.append(point(minutes: 0, level: 0.80))
        history.append(point(minutes: 0.5, level: 0.79))
        XCTAssertEqual(history.points.count, 1)
        XCTAssertEqual(history.points.last?.level, 0.79)
    }

    func testOldPointsAreDropped() {
        var history = BatteryHistory()
        history.append(point(minutes: 0, level: 0.90))
        history.append(point(minutes: 60, level: 0.85))
        history.append(point(minutes: 25 * 60, level: 0.40))
        // 第一个点距最新的点超过 24 小时
        XCTAssertEqual(history.points.map(\.level), [0.85, 0.40])
    }

    func testDischargeRate() throws {
        var history = BatteryHistory()
        history.append(point(minutes: 0, level: 0.80))
        history.append(point(minutes: 30, level: 0.76))
        history.append(point(minutes: 60, level: 0.72))
        let rate = try XCTUnwrap(history.recentLevelPerHour())
        XCTAssertEqual(rate, -0.08, accuracy: 1e-9)
    }

    func testRateOnlyUsesCurrentPlugState() throws {
        var history = BatteryHistory()
        history.append(point(minutes: 0, level: 0.90))
        history.append(point(minutes: 60, level: 0.40))
        history.append(point(minutes: 70, level: 0.42, charging: true))
        history.append(point(minutes: 100, level: 0.60, charging: true))
        let rate = try XCTUnwrap(history.recentLevelPerHour())
        // 只看插电后的两个点：30 分钟涨了 18%
        XCTAssertEqual(rate, 0.36, accuracy: 1e-9)
    }

    func testRateNeedsMinimumSpan() {
        var history = BatteryHistory()
        history.append(point(minutes: 0, level: 0.50, charging: true))
        history.append(point(minutes: 5, level: 0.53, charging: true))
        XCTAssertNil(history.recentLevelPerHour())
    }

    func testRoundTripsThroughJSON() throws {
        var history = BatteryHistory()
        history.append(point(minutes: 0, level: 0.5))
        history.append(point(minutes: 10, level: 0.6, charging: true))
        let decoded = try JSONDecoder().decode(BatteryHistory.self, from: JSONEncoder().encode(history))
        XCTAssertEqual(decoded, history)
    }
}
