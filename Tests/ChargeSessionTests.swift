import XCTest

private let origin = Date(timeIntervalSinceReferenceDate: 800_000_000)

private func at(_ seconds: TimeInterval) -> Date {
    origin.addingTimeInterval(seconds)
}

/// (分钟, 电量) → 读数
private func minuteSamples(_ levels: [(Double, Double)]) -> [ChargeSample] {
    levels.map { ChargeSample(time: at($0.0 * 60), level: $0.1) }
}

/// 按步数生成 (分钟, 电量)。参数和返回值都写明类型，避免编译器推断复杂的元组表达式超时
private func points(_ steps: ClosedRange<Int>, minute: (Int) -> Double = { Double($0) }, level: (Int) -> Double) -> [(Double, Double)] {
    steps.map { (step: Int) -> (Double, Double) in (minute(step), level(step)) }
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

    func testAutomationPlugInStartsObservedSession() throws {
        var recorder = ChargeSessionRecorder()
        XCTAssertNil(recorder.recordPlugIn(level: 0.30, at: at(0), capacityMAh: 3000))
        let current = try XCTUnwrap(recorder.current)
        XCTAssertTrue(current.startObserved)
        XCTAssertEqual(current.startDate, at(0))
        XCTAssertEqual(current.samples.count, 1)
    }

    func testAutomationPlugInWhileRecordingIsIgnored() throws {
        var recorder = ChargeSessionRecorder()
        recorder.record(level: 0.40, state: .unplugged, at: at(0), capacityMAh: nil)
        recorder.record(level: 0.40, state: .charging, at: at(1), capacityMAh: nil)
        let id = try XCTUnwrap(recorder.current).id
        XCTAssertNil(recorder.recordPlugIn(level: 0.40, at: at(2), capacityMAh: nil))
        XCTAssertEqual(try XCTUnwrap(recorder.current).id, id)
    }

    func testAutomationPlugInEndsStaleSession() throws {
        var recorder = ChargeSessionRecorder()
        recorder.record(level: 0.50, state: .charging, at: at(0), capacityMAh: nil)
        recorder.record(level: 0.60, state: .charging, at: at(600), capacityMAh: nil)
        // 之后 App 没运行，拔电没被看到；第二天插电时自动化运行
        let finished = try XCTUnwrap(recorder.recordPlugIn(level: 0.30, at: at(90_000), capacityMAh: nil))
        XCTAssertEqual(finished.endDate, at(600))
        XCTAssertFalse(finished.endObserved)
        let current = try XCTUnwrap(recorder.current)
        XCTAssertNotEqual(current.id, finished.id)
        XCTAssertTrue(current.startObserved)
        XCTAssertEqual(current.samples.first?.level, 0.30)
    }

    func testAppKeepsRecordingAfterAutomationPlugIn() throws {
        var recorder = ChargeSessionRecorder()
        recorder.recordPlugIn(level: 0.50, at: at(0), capacityMAh: nil)
        let id = try XCTUnwrap(recorder.current).id
        // App 一小时后才打开，还在充电：接着记录同一次
        XCTAssertNil(recorder.record(level: 0.80, state: .charging, at: at(3_600), capacityMAh: nil))
        let current = try XCTUnwrap(recorder.current)
        XCTAssertEqual(current.id, id)
        XCTAssertTrue(current.startObserved)
        XCTAssertEqual(current.samples.count, 2)
    }

    func testAutomationOnlySessionHasExactStartEndAndAverage() throws {
        var recorder = ChargeSessionRecorder()
        recorder.recordPlugIn(level: 0.30, at: at(0), capacityMAh: 3000)
        let finished = try XCTUnwrap(recorder.recordUnplug(level: 0.90, at: at(7_200)))
        XCTAssertNil(recorder.current)
        XCTAssertTrue(finished.startObserved)
        XCTAssertTrue(finished.endObserved)
        XCTAssertEqual(finished.endDate, at(7_200))
        let report = try XCTUnwrap(ChargeAnalyzer.report(for: finished, now: at(99_999)))
        XCTAssertEqual(report.duration, 7_200, accuracy: 1e-6)
        // 两小时 +60%：平均每小时 +30%
        XCTAssertEqual(try XCTUnwrap(report.levelPerHour), 0.30, accuracy: 1e-9)
        // 中间没有数据
        XCTAssertLessThan(report.completeness, 0.05)
    }

    func testAutomationUnplugAfterHiddenReplugEndsAtLastSample() throws {
        var recorder = ChargeSessionRecorder()
        recorder.recordPlugIn(level: 0.50, at: at(0), capacityMAh: nil)
        // 电量反而比插电时低很多：中间拔过电又插上，当时没记录到
        let finished = try XCTUnwrap(recorder.recordUnplug(level: 0.30, at: at(7_200)))
        XCTAssertEqual(finished.endDate, at(0))
        XCTAssertFalse(finished.endObserved)
    }

    func testAutomationUnplugWithoutSessionDoesNothing() {
        var recorder = ChargeSessionRecorder()
        XCTAssertNil(recorder.recordUnplug(level: 0.80, at: at(0)))
        XCTAssertNil(recorder.current)
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
        let samples = minuteSamples(points(0...30, level: { Double(20 + $0) / 100 }))
        let report = try XCTUnwrap(ChargeAnalyzer.report(for: session(samples), now: at(99_999)))
        XCTAssertEqual(report.duration, 30 * 60, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(report.levelPerHour), 0.6, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(report.averageWatts), 6.93, accuracy: 0.01)
        XCTAssertEqual(report.completeness, 1, accuracy: 1e-9)
    }

    func testNoPowerWithoutCapacity() throws {
        let samples = minuteSamples(points(0...30, level: { Double(20 + $0) / 100 }))
        let report = try XCTUnwrap(ChargeAnalyzer.report(for: session(samples, capacity: nil), now: at(99_999)))
        XCTAssertNil(report.averageWatts)
        XCTAssertNotNil(report.levelPerHour)
    }

    func testCompletenessCountsOnlyCoveredTime() {
        // 0–10 分钟和 40–50 分钟有数据，中间 30 分钟 App 没运行
        let samples = minuteSamples(points(0...10, level: { _ in 0.5 }) + points(40...50, level: { _ in 0.7 }))
        let value = ChargeAnalyzer.completeness(samples, start: at(0), end: at(50 * 60))
        XCTAssertEqual(value, 0.4, accuracy: 1e-9)
    }

    func testPeakUsesFastestWindow() throws {
        // 前 15 分钟每分钟 +1%，之后每 2 分钟 +1%
        var levels = points(0...15, level: { Double(40 + $0) / 100 })
        levels += points(1...10, minute: { 15 + Double($0) * 2 }, level: { Double(55 + $0) / 100 })
        let peak = try XCTUnwrap(ChargeAnalyzer.peakLevelPerHour(minuteSamples(levels)))
        XCTAssertEqual(peak, 0.6, accuracy: 1e-6)
    }

    func testOptimizedChargingSuspected() {
        // 20 分钟从 40% 充到 80%，然后半小时只涨到 81%
        var levels = points(0...20, level: { Double(40 + 2 * $0) / 100 })
        levels += points(21...50, level: { _ in 0.81 })
        XCTAssertEqual(ChargeAnalyzer.optimizedChargingStatus(minuteSamples(levels)), .suspected)
    }

    func testSteadyChargingIsNotOptimized() {
        // 每分钟 +1%，一路充到 100%
        let levels = points(0...60, level: { Double(40 + $0) / 100 })
        XCTAssertEqual(ChargeAnalyzer.optimizedChargingStatus(minuteSamples(levels)), .notDetected)
    }

    func testOptimizedChargingNeedsDataAroundEightyPercent() {
        let startedHigh = points(0...40, level: { Double(85 + $0 / 4) / 100 })
        XCTAssertEqual(ChargeAnalyzer.optimizedChargingStatus(minuteSamples(startedHigh)), .insufficientData)
        let stoppedEarly = points(0...20, level: { Double(40 + $0) / 100 })
        XCTAssertEqual(ChargeAnalyzer.optimizedChargingStatus(minuteSamples(stoppedEarly)), .insufficientData)
    }
}
