import XCTest

private let origin = Date(timeIntervalSinceReferenceDate: 820_000_000)

private func at(_ seconds: TimeInterval) -> Date {
    origin.addingTimeInterval(seconds)
}

/// 一次充电：从 startPercent 起，每 secondsPerPercent 秒涨 1%，涨到 endPercent。
/// 每次变化记一个点（和 App 记录的方式一样）；gapAt 指定在哪个百分比之前断开（App 没在运行）
private func makeSession(accessory: UUID?, startPercent: Int, endPercent: Int, secondsPerPercent: Double,
                         offset: TimeInterval = 0, gapAt: Int? = nil, capacity: Int? = 3000,
                         thermal: ThermalLevel? = nil) -> ChargeSession {
    var samples: [ChargeSample] = []
    var time: TimeInterval = offset
    for percent in startPercent...endPercent {
        if let gapAt, percent == gapAt {
            time += 600
        }
        samples.append(ChargeSample(time: at(time), level: Double(percent) / 100))
        time += secondsPerPercent
    }
    return ChargeSession(
        id: UUID(),
        startDate: at(offset),
        endDate: samples.last?.time,
        startObserved: true,
        endObserved: true,
        samples: samples,
        tag: nil,
        capacityMAh: capacity,
        accessoryID: accessory,
        peakThermal: thermal)
}

final class AccessoryBookTests: XCTestCase {
    func testAddTrimsAndRejectsEmptyOrDuplicate() throws {
        var book = AccessoryBook()
        let bedside = try XCTUnwrap(book.add(name: "  床头充电器＋白色线 ", at: at(0)))
        XCTAssertEqual(bedside.name, "床头充电器＋白色线")
        XCTAssertNil(book.add(name: "   ", at: at(1)))
        // 重名直接返回已有的，不会建出两个
        XCTAssertEqual(book.add(name: "床头充电器＋白色线", at: at(2))?.id, bedside.id)
        XCTAssertEqual(book.profiles.count, 1)
        // 名字太长截断
        let long = try XCTUnwrap(book.add(name: String(repeating: "长", count: 40), at: at(3)))
        XCTAssertEqual(long.name.count, AccessoryBook.maxNameLength)
    }

    func testRecentOrderAndLastUsed() throws {
        var book = AccessoryBook()
        let a = try XCTUnwrap(book.add(name: "A", at: at(0)))
        let b = try XCTUnwrap(book.add(name: "B", at: at(1)))
        let c = try XCTUnwrap(book.add(name: "C", at: at(2)))
        XCTAssertNil(book.lastUsed)
        book.markUsed(a.id)
        book.markUsed(b.id)
        XCTAssertEqual(book.lastUsed?.id, b.id)
        // 用过的按最近顺序在前，没用过的按创建时间（新的在前）排在后面
        XCTAssertEqual(book.sortedByRecent.map(\.id), [b.id, a.id, c.id])
        book.markUsed(a.id)
        XCTAssertEqual(book.sortedByRecent.map(\.id), [a.id, b.id, c.id])
    }

    func testRenameAndRemove() throws {
        var book = AccessoryBook()
        let a = try XCTUnwrap(book.add(name: "A", at: at(0)))
        let b = try XCTUnwrap(book.add(name: "B", at: at(1)))
        XCTAssertTrue(book.rename(a.id, to: "办公室充电器"))
        XCTAssertEqual(book.profile(a.id)?.name, "办公室充电器")
        XCTAssertFalse(book.rename(b.id, to: "办公室充电器"), "不能和别的组合重名")
        XCTAssertFalse(book.rename(b.id, to: " "))
        book.markUsed(a.id)
        book.remove(a.id)
        XCTAssertNil(book.profile(a.id))
        XCTAssertNil(book.lastUsed)
    }

    func testBookSurvivesJSONRoundTrip() throws {
        var book = AccessoryBook()
        let a = try XCTUnwrap(book.add(name: "A", at: at(0)))
        book.markUsed(a.id)
        let decoded = try JSONDecoder().decode(AccessoryBook.self, from: JSONEncoder().encode(book))
        XCTAssertEqual(decoded, book)
    }
}

final class AccessoryLinkTests: XCTestCase {
    func testRecorderKeepsAccessoryAndPeakThermalInFinishedSession() throws {
        var recorder = ChargeSessionRecorder()
        let accessory = UUID()
        recorder.record(level: 0.40, state: .unplugged, at: at(0), capacityMAh: 3000)
        recorder.record(level: 0.40, state: .charging, at: at(1), capacityMAh: 3000, thermal: .nominal)
        recorder.assignAccessory(accessory)
        recorder.record(level: 0.45, state: .charging, at: at(60), capacityMAh: 3000, thermal: .fair)
        recorder.record(level: 0.50, state: .charging, at: at(120), capacityMAh: 3000, thermal: .nominal)
        let finished = try XCTUnwrap(recorder.record(level: 0.50, state: .unplugged, at: at(125), capacityMAh: 3000))
        XCTAssertEqual(finished.accessoryID, accessory)
        // 期间最高的温控状态
        XCTAssertEqual(finished.peakThermal, .fair)
        // 下一次充电不会自动带上
        recorder.record(level: 0.50, state: .charging, at: at(130), capacityMAh: 3000)
        XCTAssertNil(try XCTUnwrap(recorder.current).accessoryID)
    }

    func testUnlinkingKeepsSessions() {
        let removed = UUID()
        let kept = UUID()
        let sessions = [
            makeSession(accessory: removed, startPercent: 30, endPercent: 40, secondsPerPercent: 60),
            makeSession(accessory: kept, startPercent: 30, endPercent: 40, secondsPerPercent: 60),
        ]
        let result = sessions.unlinking(accessory: removed)
        XCTAssertEqual(result.count, 2)
        XCTAssertNil(result[0].accessoryID)
        XCTAssertEqual(result[1].accessoryID, kept)
    }

    func testOldSessionWithoutAccessoryFieldsStillDecodes() throws {
        let session = makeSession(accessory: UUID(), startPercent: 30, endPercent: 35, secondsPerPercent: 60, thermal: .fair)
        let data = try JSONEncoder().encode(session)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "accessoryID")
        object.removeValue(forKey: "peakThermal")
        let decoded = try JSONDecoder().decode(ChargeSession.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(decoded.accessoryID)
        XCTAssertNil(decoded.peakThermal)
        XCTAssertEqual(decoded.samples.count, session.samples.count)
    }
}

final class AccessoryComparisonTests: XCTestCase {
    private let fast = UUID()
    private let slow = UUID()

    func testNoRecordsIsInsufficient() {
        let sessions = [makeSession(accessory: fast, startPercent: 20, endPercent: 60, secondsPerPercent: 30)]
        let result = AccessoryComparison.compare(fast, slow, sessions: sessions)
        XCTAssertEqual(result.verdict, .insufficient(.noRecords(slow)))
    }

    func testNoOverlappingRangeIsInsufficient() {
        let sessions = [
            makeSession(accessory: fast, startPercent: 10, endPercent: 30, secondsPerPercent: 30),
            makeSession(accessory: slow, startPercent: 60, endPercent: 90, secondsPerPercent: 60),
        ]
        let result = AccessoryComparison.compare(fast, slow, sessions: sessions)
        XCTAssertEqual(result.verdict, .insufficient(.noCommonRange))
        XCTAssertNil(result.range)
    }

    func testOneRecordEachIsPreliminary() throws {
        let sessions = [
            makeSession(accessory: fast, startPercent: 20, endPercent: 70, secondsPerPercent: 30),
            makeSession(accessory: slow, startPercent: 30, endPercent: 80, secondsPerPercent: 60),
        ]
        let result = AccessoryComparison.compare(fast, slow, sessions: sessions)
        XCTAssertEqual(result.verdict, .preliminary)
        // 两组都覆盖的最宽区间：31% → 70%（刚涨到 31% 才有准确的时间）
        XCTAssertEqual(result.range, 31...70)
        XCTAssertEqual(try XCTUnwrap(result.a.medianLevelPerHour), 1.2, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(result.b.medianLevelPerHour), 0.6, accuracy: 1e-6)
        // 39 个百分点，每 30 秒 1%
        XCTAssertEqual(try XCTUnwrap(result.a.medianDuration), 39 * 30, accuracy: 1e-6)
        // 每小时 120%，3000 mAh：1.2 × 3.0 × 3.85 = 13.86 W
        XCTAssertEqual(try XCTUnwrap(result.a.medianWatts), 13.86, accuracy: 0.01)
    }

    func testFasterVerdictWithEnoughRecords() {
        let sessions = [
            makeSession(accessory: fast, startPercent: 20, endPercent: 70, secondsPerPercent: 30),
            makeSession(accessory: fast, startPercent: 25, endPercent: 75, secondsPerPercent: 32, offset: 90_000),
            makeSession(accessory: slow, startPercent: 30, endPercent: 80, secondsPerPercent: 60, offset: 180_000),
            makeSession(accessory: slow, startPercent: 22, endPercent: 66, secondsPerPercent: 58, offset: 270_000),
        ]
        let result = AccessoryComparison.compare(fast, slow, sessions: sessions)
        XCTAssertEqual(result.a.runs.count, 2)
        XCTAssertEqual(result.b.runs.count, 2)
        guard case let .faster(winner, difference) = result.verdict else {
            return XCTFail("应该给出结论：\(result.verdict)")
        }
        XCTAssertEqual(winner, fast)
        XCTAssertGreaterThan(difference, 0.8)
        XCTAssertFalse(result.hadHeat)
    }

    func testSimilarWhenDifferenceIsSmall() {
        let sessions = [
            makeSession(accessory: fast, startPercent: 20, endPercent: 70, secondsPerPercent: 30),
            makeSession(accessory: fast, startPercent: 20, endPercent: 70, secondsPerPercent: 31, offset: 90_000),
            makeSession(accessory: slow, startPercent: 20, endPercent: 70, secondsPerPercent: 32, offset: 180_000),
            makeSession(accessory: slow, startPercent: 20, endPercent: 70, secondsPerPercent: 31, offset: 270_000),
        ]
        let result = AccessoryComparison.compare(fast, slow, sessions: sessions)
        guard case let .similar(difference) = result.verdict else {
            return XCTFail("差别小于 10% 应该算差不多：\(result.verdict)")
        }
        XCTAssertLessThan(difference, AccessoryComparison.similarThreshold)
    }

    func testPrefersRangeBelowEightyPercent() {
        let sessions = [
            makeSession(accessory: fast, startPercent: 50, endPercent: 100, secondsPerPercent: 30),
            makeSession(accessory: slow, startPercent: 50, endPercent: 100, secondsPerPercent: 60),
        ]
        let result = AccessoryComparison.compare(fast, slow, sessions: sessions)
        // 80% 以后系统常放慢充电，有 80% 以下的区间就不用更宽的 51...100
        XCTAssertEqual(result.range, 51...80)
    }

    func testGapInRecordingIsNotUsed() {
        // 慢的那组在 45% 前断开了 10 分钟：只有 46% 以后的数据可以和快的那组比
        let sessions = [
            makeSession(accessory: fast, startPercent: 20, endPercent: 70, secondsPerPercent: 30),
            makeSession(accessory: slow, startPercent: 20, endPercent: 70, secondsPerPercent: 60, gapAt: 45),
        ]
        let result = AccessoryComparison.compare(fast, slow, sessions: sessions)
        XCTAssertEqual(result.range, 46...70)
        XCTAssertEqual(result.b.medianLevelPerHour ?? 0, 0.6, accuracy: 1e-6)
    }

    func testHeatIsFlagged() {
        let sessions = [
            makeSession(accessory: fast, startPercent: 20, endPercent: 70, secondsPerPercent: 30, thermal: .fair),
            makeSession(accessory: slow, startPercent: 20, endPercent: 70, secondsPerPercent: 60),
        ]
        XCTAssertTrue(AccessoryComparison.compare(fast, slow, sessions: sessions).hadHeat)
    }

    func testMedian() {
        XCTAssertNil(AccessoryComparison.median([]))
        XCTAssertEqual(AccessoryComparison.median([3, 1, 2]), 2)
        XCTAssertEqual(AccessoryComparison.median([4, 1, 2, 3]), 2.5)
    }
}
