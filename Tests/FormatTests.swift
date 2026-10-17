import XCTest

final class FormatTests: XCTestCase {
    func testSpeedUnitsAndPrecision() {
        XCTAssertEqual(Format.speed(0), "0 B/s")
        XCTAssertEqual(Format.speed(-5), "0 B/s")
        XCTAssertEqual(Format.speed(999), "999 B/s")
        XCTAssertEqual(Format.speed(1_000), "1.00 KB/s")
        XCTAssertEqual(Format.speed(12_340), "12.3 KB/s")
        XCTAssertEqual(Format.speed(123_456), "123 KB/s")
        XCTAssertEqual(Format.speed(1_500_000), "1.50 MB/s")
        XCTAssertEqual(Format.speed(2_000_000_000), "2.00 GB/s")
    }

    func testMbps() {
        XCTAssertEqual(Format.mbps(87.64), "87.6 Mbps")
        XCTAssertEqual(Format.mbps(250.4), "250 Mbps")
    }

    func testWatts() {
        XCTAssertEqual(Format.watts(12.34), "12.3 W")
    }

    func testSpeedParts() {
        XCTAssertEqual(Format.speedParts(1_500_000).value, "1.50")
        XCTAssertEqual(Format.speedParts(1_500_000).unit, "MB/s")
    }

    func testCompactSpeed() {
        XCTAssertEqual(Format.compactSpeed(0), "0B")
        XCTAssertEqual(Format.compactSpeed(850), "850B")
        XCTAssertEqual(Format.compactSpeed(1_500), "1.5K")
        XCTAssertEqual(Format.compactSpeed(12_340), "12K")
        XCTAssertEqual(Format.compactSpeed(2_500_000), "2.5M")
    }

    func testStorageUsesDecimalAndMemoryUsesBinary() {
        XCTAssertEqual(Format.storageParts(128_000_000_000).value, "128")
        XCTAssertEqual(Format.storageParts(42_100_000_000).value, "42.1")
        XCTAssertEqual(Format.storageParts(42_100_000_000).unit, "GB")
        XCTAssertEqual(Format.memoryParts(6 << 30).value, "6.0")
        XCTAssertEqual(Format.memoryParts(6 << 30).unit, "GB")
        XCTAssertEqual(Format.memoryParts(512 << 20).value, "512")
        XCTAssertEqual(Format.memoryParts(512 << 20).unit, "MB")
    }

    func testLevelRate() {
        XCTAssertEqual(Format.levelRate(0.18), "+18%/h")
        XCTAssertEqual(Format.levelRate(-0.08), "-8%/h")
    }

    func testDuration() {
        XCTAssertEqual(Format.duration(25 * 60), "25 分钟")
        XCTAssertEqual(Format.duration(80 * 60), "1 小时 20 分")
        XCTAssertEqual(Format.duration(120 * 60), "2 小时")
    }

    func testOldSnapshotWithoutLevelPerHourStillDecodes() throws {
        // 新增字段不能让旧版本存下的快照解码失败
        let data = try JSONEncoder().encode(MetricsSnapshot.placeholder)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var battery = try XCTUnwrap(object["battery"] as? [String: Any])
        battery.removeValue(forKey: "levelPerHour")
        object["battery"] = battery
        let stripped = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(MetricsSnapshot.self, from: stripped)
        XCTAssertNil(decoded.battery.levelPerHour)
        XCTAssertEqual(decoded.battery.level, MetricsSnapshot.placeholder.battery.level)
    }

    func testSnapshotRoundTripsThroughJSON() throws {
        // 小组件靠 JSON 读取主 App 存的快照，字段改动不能破坏编解码
        let data = try JSONEncoder().encode(MetricsSnapshot.placeholder)
        let decoded = try JSONDecoder().decode(MetricsSnapshot.self, from: data)
        XCTAssertEqual(decoded.battery, MetricsSnapshot.placeholder.battery)
        XCTAssertEqual(decoded.network, MetricsSnapshot.placeholder.network)
    }
}
