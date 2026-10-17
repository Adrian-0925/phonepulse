import XCTest

private let origin = Date(timeIntervalSinceReferenceDate: 800_000_000)

private func at(_ seconds: TimeInterval) -> Date {
    origin.addingTimeInterval(seconds)
}

/// (分钟, 电量) → 读数
private func minuteSamples(_ levels: [(Double, Double)]) -> [ChargeSample] {
    levels.map { ChargeSample(time: at($0.0 * 60), level: $0.1) }
}

final class ChargeSessionRecorderTests: XCTestCase {
    func testObservedPlugInAndUnplug() throws {
        var recorder = ChargeSessionRecorder()
        recorder.record(level: 0.40, state: .unplugged, at: at(0), capacityMAh: 3000)
        recorder.record(level: 0.40, state: .charging, at: at(1), capacityMAh: 3000)
        let started = try XCTUnwrap(recorder.current)
        XCTAssertTrue(started.startObserved)
        XCTAssertEqual(started.startDate, at(1))

        for minute in 1...30 {
            recorder.record(level: 0.40 + Double(minute) * 0.01, state: .charging, at: at(Double(minute) * 60), capacityMAh: 3000)
        }
        let finished = try XCTUnwrap(recorder.record(level: 0.70, state: .unplugged, at: at(30 * 60 + 5), capacityMAh: 3000))
        XCTAssertTrue(finished.endObserved)
        XCTAssertEqual(finished.endDate, at(30 * 60 + 5))
        XCTAssertNil(recorder.current)
    }

    func testStartNotObservedWhenAppOpensWhilePluggedIn() throws {
        var recorder = ChargeSessionRecorder()
        recorder.record(level: 0.55, state: .charging, at: at(0), capacityMAh: nil)
        XCTAssertFalse(try XCTUnwrap(recorder.current).startObserved)
    }

    func testSamplesAreThinnedToAboutOnePerMinute() throws {
        var recorder = ChargeSessionRecorder()
        for second in 0...180 {
            recorder.record(level: 0.50, state: .charging, at: at(Double(second)), capacityMAh: nil)
        }
        // 第 0、60、120、180 秒各一个点
        XCTAssertEqual(try XCTUnwrap(recorder.current).samples.count, 4)

        recorder.record(level: 0.51, state: .charging, at: at(181), capacityMAh: nil)
        // 电量变化时立即记一个点
        XCTAssertEqual(try XCTUnwrap(recorder.current).samples.last?.level, 0.51)
    }

    func testUnplugAfterGapEndsAtLastSample() throws {
        var recorder = ChargeSessionRecorder()
        recorder.record(level: 0.50, state: .charging, at: at(0), capacityMAh: nil)
        recorder.record(level: 0.60, state: .charging, at: at(600), capacityMAh: nil)
        // App 关了一个小时，再打开时已经拔电
        let finished = try XCTUnwrap(recorder.record(level: 0.70, state: .unplugged, at: at(4_200), capacityMAh: nil))
        XCTAssertFalse(finished.endObserved)
        XCTAssertEqual(finished.endDate, at(600))
    }

    func testReplugWhileAppClosedStartsNewSession() throws {
        var recorder = ChargeSessionRecorder()
        recorder.record(level: 0.70, state: .charging, at: at(0), capacityMAh: nil)
        recorder.record(level: 0.80, state: .charging, at: at(600), capacityMAh: nil)
        // 再打开 App 时还插着电，但电量比上次低很多：中间拔过电又插上了
        let finished = try XCTUnwrap(recorder.record(level: 0.50, state: .charging, at: at(10_000), capacityMAh: nil))
        XCTAssertEqual(finished.endDate, at(600))
        let current = try XCTUnwrap(recorder.current)
        XCTAssertNotEqual(current.id, finished.id)
        XCTAssertFalse(current.startObserved)
        XCTAssertEqual(current.samples.first?.level, 0.50)
    }

    func testFullStillCountsAsPluggedInAndUnknownIsIgnored() throws {
        var recorder = ChargeSessionRecorder()
        recorder.record(level: 0.99, state: .charging, at: at(0), capacityMAh: nil)
        recorder.record(level: 1.0, state: .full, at: at(60), capacityMAh: nil)
        XCTAssertNil(recorder.record(level: nil, state: .unknown, at: at(61), capacityMAh: nil))
        XCTAssertEqual(try XCTUnwrap(recorder.current).samples.count, 2)
    }

    func testRecorderSurvivesJSONRoundTrip() throws {
        var recorder = ChargeSessionRecorder()
        recorder.record(level: 0.30, state: .unplugged, at: at(0), capacityMAh: nil)
        recorder.record(level: 0.30, state: .charging, at: at(1), capacityMAh: 3000)
        let decoded = try JSONDecoder().decode(ChargeSessionRecorder.self, from: JSONEncoder().encode(recorder))
        XCTAssertEqual(decoded, recorder)
    }
}

final class ChargeAnalyzerTests: XCTestCase {
    private func session(_ samples: [ChargeSample], end: Date? = nil, capacity: Int? = 3000) -> ChargeSession {
        ChargeSession(
            id: UUID(),
            startDate: samples.first?.time ?? origin,
            endDate: end ?? samples.last?.time,
            startObserved: true,
            endObserved: true,
            samples: samples,
            tag: nil,
            capacityMAh: capacity)
    }

    func testAveragePowerAndDuration() throws {
        // 每分钟 +1%，30 分钟：0.6 /h × 3.0 Ah × 3.85 V = 6.93 W
        let samples = minuteSamples((0...30).map { (Double($0), Double(20 + $0) / 100) })
        let report = try XCTUnwrap(ChargeAnalyzer.report(for: session(samples), now: at(99_999)))
        XCTAssertEqual(report.duration, 30 * 60, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(report.levelPerHour), 0.6, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(report.averageWatts), 6.93, accuracy: 0.01)
        XCTAssertEqual(report.completeness, 1, accuracy: 1e-9)
    }

    func testNoPowerWithoutCapacity() throws {
        let samples = minuteSamples((0...30).map { (Double($0), Double(20 + $0) / 100) })
        let report = try XCTUnwrap(ChargeAnalyzer.report(for: session(samples, capacity: nil), now: at(99_999)))
        XCTAssertNil(report.averageWatts)
        XCTAssertNotNil(report.levelPerHour)
    }

    func testCompletenessCountsOnlyCoveredTime() {
        // 0–10 分钟和 40–50 分钟有数据，中间 30 分钟 App 没运行
        let samples = minuteSamples((0...10).map { (Double($0), 0.5) } + (40...50).map { (Double($0), 0.7) })
        let value = ChargeAnalyzer.completeness(samples, start: at(0), end: at(50 * 60))
        XCTAssertEqual(value, 0.4, accuracy: 1e-9)
    }

    func testPeakUsesFastestWindow() throws {
        // 前 15 分钟每分钟 +1%，之后每 2 分钟 +1%
        var levels: [(Double, Double)] = (0...15).map { (Double($0), Double(40 + $0) / 100) }
        levels += (1...10).map { (15 + Double($0) * 2, Double(55 + $0) / 100) }
        let peak = try XCTUnwrap(ChargeAnalyzer.peakLevelPerHour(minuteSamples(levels)))
        XCTAssertEqual(peak, 0.6, accuracy: 1e-6)
    }

    func testOptimizedChargingSuspected() {
        // 20 分钟从 40% 充到 80%，然后半小时只涨到 81%
        var levels: [(Double, Double)] = (0...20).map { (Double($0), Double(40 + 2 * $0) / 100) }
        levels += (21...50).map { (Double($0), 0.81) }
        XCTAssertEqual(ChargeAnalyzer.optimizedChargingStatus(minuteSamples(levels)), .suspected)
    }

    func testSteadyChargingIsNotOptimized() {
        // 每分钟 +1%，一路充到 100%
        let levels = (0...60).map { (Double($0), Double(40 + $0) / 100) }
        XCTAssertEqual(ChargeAnalyzer.optimizedChargingStatus(minuteSamples(levels)), .notDetected)
    }

    func testOptimizedChargingNeedsDataAroundEightyPercent() {
        let startedHigh = (0...40).map { (Double($0), Double(85 + $0 / 4) / 100) }
        XCTAssertEqual(ChargeAnalyzer.optimizedChargingStatus(minuteSamples(startedHigh)), .insufficientData)
        let stoppedEarly = (0...20).map { (Double($0), Double(40 + $0) / 100) }
        XCTAssertEqual(ChargeAnalyzer.optimizedChargingStatus(minuteSamples(stoppedEarly)), .insufficientData)
    }
}
