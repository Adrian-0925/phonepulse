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

    func testSnapshotRoundTripsThroughJSON() throws {
        // 小组件靠 JSON 读取主 App 存的快照，字段改动不能破坏编解码
        let data = try JSONEncoder().encode(MetricsSnapshot.placeholder)
        let decoded = try JSONDecoder().decode(MetricsSnapshot.self, from: data)
        XCTAssertEqual(decoded.battery, MetricsSnapshot.placeholder.battery)
        XCTAssertEqual(decoded.network, MetricsSnapshot.placeholder.network)
    }
}
