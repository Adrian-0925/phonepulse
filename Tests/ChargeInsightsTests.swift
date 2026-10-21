import XCTest

private let origin = Date(timeIntervalSinceReferenceDate: 800_000_000)

private func at(_ seconds: TimeInterval) -> Date {
    origin.addingTimeInterval(seconds)
}

/// 从 startPercent 匀速充到 endPercent，每涨 1% 用 secondsPerPercent 秒（不超过 150 秒，数据是连续的）
private func session(from startPercent: Int, to endPercent: Int, secondsPerPercent: Double, start: Date = origin,
                     observed: Bool = true, thermal: ThermalLevel? = nil) -> ChargeSession {
    let samples: [ChargeSample] = (0...(endPercent - startPercent)).map { (step: Int) -> ChargeSample in
        ChargeSample(time: start.addingTimeInterval(Double(step) * secondsPerPercent), level: Double(startPercent + step) / 100)
    }
    return ChargeSession(
        id: UUID(),
        startDate: start,
        endDate: samples.last?.time,
        startObserved: observed,
        endObserved: true,
        samples: samples,
        tag: nil,
        capacityMAh: 3000,
        peakThermal: thermal)
}

final class SpeedVersusUsualTests: XCTestCase {
    private var usual: [ChargeSession] {
        [session(from: 20, to: 70, secondsPerPercent: 60), session(from: 20, to: 70, secondsPerPercent: 60)]
    }

    func testFasterThanUsual() throws {
        let result = ChargeInsights.speedVersusUsual(session(from: 20, to: 70, secondsPerPercent: 45), history: usual)
        XCTAssertEqual(result.range, 21...70)
        XCTAssertEqual(result.baselineCount, 2)
        XCTAssertEqual(try XCTUnwrap(result.duration), 49 * 45, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(result.usualDuration), 49 * 60, accuracy: 1e-6)
        guard case let .faster(by: value) = result.verdict else {
            return XCTFail("应该比平时快，实际是 \(result.verdict)")
        }
        // 速度是平时的 60/45 倍
        XCTAssertEqual(value, 1.0 / 3.0, accuracy: 1e-9)
    }

    func testSlowerThanUsual() {
        let result = ChargeInsights.speedVersusUsual(session(from: 20, to: 70, secondsPerPercent: 75), history: usual)
        guard case let .slower(by: value) = result.verdict else {
            return XCTFail("应该比平时慢，实际是 \(result.verdict)")
        }
        // 速度是平时的 60/75 = 0.8 倍，慢 20%
        XCTAssertEqual(value, 0.2, accuracy: 1e-9)
    }

    func testSmallDifferenceIsSimilar() {
        let result = ChargeInsights.speedVersusUsual(session(from: 20, to: 70, secondsPerPercent: 63), history: usual)
        guard case .similar = result.verdict else {
            return XCTFail("差别不到 10% 应该算差不多，实际是 \(result.verdict)")
        }
    }

    func testNeedsTwoBaselineRecords() {
        let result = ChargeInsights.speedVersusUsual(session(from: 20, to: 70, secondsPerPercent: 45),
                                                     history: [session(from: 20, to: 70, secondsPerPercent: 60)])
        XCTAssertEqual(result.verdict, .insufficient)
        XCTAssertEqual(result.baselineCount, 1)
        XCTAssertNotNil(result.range)
    }

    func testSessionItselfIsNotPartOfBaseline() {
        let target = session(from: 20, to: 70, secondsPerPercent: 45)
        let result = ChargeInsights.speedVersusUsual(target, history: [target, session(from: 20, to: 70, secondsPerPercent: 60)])
        XCTAssertEqual(result.baselineCount, 1)
        XCTAssertEqual(result.verdict, .insufficient)
    }

    func testNoOverlappingRange() {
        let result = ChargeInsights.speedVersusUsual(session(from: 20, to: 35, secondsPerPercent: 60),
                                                     history: [session(from: 50, to: 90, secondsPerPercent: 60),
                                                               session(from: 50, to: 90, secondsPerPercent: 60)])
        XCTAssertNil(result.range)
        XCTAssertEqual(result.verdict, .insufficient)
    }

    func testPrefersRangeCoveredByMoreRecords() {
        // 只有一条记录覆盖 10%→90%，另外两条只覆盖 30%→60%：宁可窄一点，也要有两条以上的记录可比
        let history = [
            session(from: 10, to: 90, secondsPerPercent: 60),
            session(from: 30, to: 60, secondsPerPercent: 60),
            session(from: 30, to: 60, secondsPerPercent: 60),
        ]
        let result = ChargeInsights.speedVersusUsual(session(from: 10, to: 90, secondsPerPercent: 60), history: history)
        XCTAssertEqual(result.range, 31...60)
        XCTAssertEqual(result.baselineCount, 3)
    }
}

final class ChargeHabitsTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }

    private func date(day: Int, hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour)) ?? origin
    }

    func testDayPeriodBoundaries() {
        XCTAssertEqual(DayPeriod(hour: 0), .lateNight)
        XCTAssertEqual(DayPeriod(hour: 4), .lateNight)
        XCTAssertEqual(DayPeriod(hour: 5), .morning)
        XCTAssertEqual(DayPeriod(hour: 12), .noon)
        XCTAssertEqual(DayPeriod(hour: 18), .evening)
        XCTAssertEqual(DayPeriod(hour: 23), .evening)
    }

    func testTypicalLevelsAndCommonPeriod() throws {
        let sessions = [
            session(from: 20, to: 80, secondsPerPercent: 60, start: date(day: 1, hour: 22)),
            session(from: 30, to: 90, secondsPerPercent: 60, start: date(day: 2, hour: 23)),
            session(from: 40, to: 100, secondsPerPercent: 60, start: date(day: 3, hour: 9)),
        ]
        let habits = try XCTUnwrap(ChargeInsights.habits(sessions, calendar: calendar))
        XCTAssertEqual(habits.sessionCount, 3)
        XCTAssertEqual(try XCTUnwrap(habits.typicalStartLevel), 0.30, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(habits.typicalEndLevel), 0.90, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(habits.typicalDuration), 3600, accuracy: 1e-6)
        XCTAssertEqual(habits.commonStartPeriod, .evening)
        XCTAssertEqual(habits.commonStartCount, 2)
    }

    func testNoPeriodWithoutClearMajority() throws {
        let sessions = [
            session(from: 20, to: 80, secondsPerPercent: 60, start: date(day: 1, hour: 22)),
            session(from: 20, to: 80, secondsPerPercent: 60, start: date(day: 2, hour: 9)),
            session(from: 20, to: 80, secondsPerPercent: 60, start: date(day: 3, hour: 15)),
            session(from: 20, to: 80, secondsPerPercent: 60, start: date(day: 4, hour: 23)),
        ]
        // 晚上 2 次、上午 1 次、下午 1 次：没超过一半
        XCTAssertNil(try XCTUnwrap(ChargeInsights.habits(sessions, calendar: calendar)).commonStartPeriod)
    }

    func testUnobservedStartsDoNotCountForPeriod() throws {
        let sessions = [
            session(from: 20, to: 80, secondsPerPercent: 60, start: date(day: 1, hour: 22)),
            session(from: 20, to: 80, secondsPerPercent: 60, start: date(day: 2, hour: 22), observed: false),
            session(from: 20, to: 80, secondsPerPercent: 60, start: date(day: 3, hour: 22), observed: false),
        ]
        let habits = try XCTUnwrap(ChargeInsights.habits(sessions, calendar: calendar))
        XCTAssertNil(habits.commonStartPeriod)
        XCTAssertEqual(habits.observedStartCount, 1)
    }

    func testNeedsEnoughRecords() {
        let sessions = [session(from: 20, to: 80, secondsPerPercent: 60), session(from: 20, to: 80, secondsPerPercent: 60)]
        XCTAssertNil(ChargeInsights.habits(sessions, calendar: calendar))
    }
}

final class RecentChargingTests: XCTestCase {
    func testCountsOnlyRecentDays() {
        let now = at(30 * 86_400)
        let sessions = [
            session(from: 20, to: 100, secondsPerPercent: 60, start: at(28 * 86_400)),
            session(from: 50, to: 80, secondsPerPercent: 60, start: at(27 * 86_400), thermal: .fair),
            session(from: 10, to: 90, secondsPerPercent: 60, start: at(20 * 86_400)),
        ]
        let recent = ChargeInsights.recent(sessions, now: now)
        XCTAssertEqual(recent.days, 7)
        XCTAssertEqual(recent.count, 2)
        XCTAssertEqual(recent.totalGained, 1.1, accuracy: 1e-9)
        XCTAssertEqual(recent.reachedFullCount, 1)
        XCTAssertEqual(recent.heatCount, 1)
        XCTAssertEqual(recent.optimizedCount, 0)
    }

    func testEmptyHistory() {
        let recent = ChargeInsights.recent([], now: origin)
        XCTAssertEqual(recent.count, 0)
        XCTAssertEqual(recent.totalGained, 0)
    }
}
