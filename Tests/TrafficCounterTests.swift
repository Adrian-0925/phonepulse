import XCTest

final class TrafficCounterTests: XCTestCase {
    func testFirstReadingOnlySetsBaseline() {
        var counter = TrafficCounter()
        let delta = counter.update(with: [InterfaceReading(name: "en0", receivedBytes: 5_000_000, sentBytes: 1_000_000)])
        XCTAssertEqual(delta, TrafficCounter.Delta(received: 0, sent: 0))
        XCTAssertEqual(counter.sessionWifiBytes, 0)
    }

    func testNormalIncrease() {
        var counter = TrafficCounter()
        _ = counter.update(with: [InterfaceReading(name: "en0", receivedBytes: 1_000, sentBytes: 500)])
        let delta = counter.update(with: [InterfaceReading(name: "en0", receivedBytes: 4_000, sentBytes: 700)])
        XCTAssertEqual(delta, TrafficCounter.Delta(received: 3_000, sent: 200))
        XCTAssertEqual(counter.sessionWifiBytes, 3_200)
    }

    func testWrapAroundIsCountedAsSmallIncrease() {
        var counter = TrafficCounter()
        _ = counter.update(with: [InterfaceReading(name: "en0", receivedBytes: UInt32.max - 99, sentBytes: 0)])
        let delta = counter.update(with: [InterfaceReading(name: "en0", receivedBytes: 50, sentBytes: 0)])
        // 从 max-99 走到 max 是 99，再回绕到 0 是 1，再到 50 是 50
        XCTAssertEqual(delta.received, 150)
    }

    func testInterfaceResetDoesNotProduceHugeSpike() {
        var counter = TrafficCounter()
        _ = counter.update(with: [InterfaceReading(name: "pdp_ip0", receivedBytes: 3_000_000_000, sentBytes: 0)])
        // 开关飞行模式后计数从头开始：不能算成约 1.3 GB 的回绕增量
        let delta = counter.update(with: [InterfaceReading(name: "pdp_ip0", receivedBytes: 2_000, sentBytes: 0)])
        XCTAssertEqual(delta.received, 2_000)
    }

    func testWifiAndCellularAreSeparated() {
        var counter = TrafficCounter()
        _ = counter.update(with: [
            InterfaceReading(name: "en0", receivedBytes: 0, sentBytes: 0),
            InterfaceReading(name: "pdp_ip0", receivedBytes: 0, sentBytes: 0),
        ])
        _ = counter.update(with: [
            InterfaceReading(name: "en0", receivedBytes: 100, sentBytes: 10),
            InterfaceReading(name: "pdp_ip0", receivedBytes: 300, sentBytes: 30),
        ])
        XCTAssertEqual(counter.sessionWifiBytes, 110)
        XCTAssertEqual(counter.sessionCellularBytes, 330)
    }

    func testVPNAndOtherInterfacesAreIgnored() {
        var counter = TrafficCounter()
        let names = ["utun0", "lo0", "awdl0", "en2"]
        _ = counter.update(with: names.map { InterfaceReading(name: $0, receivedBytes: 0, sentBytes: 0) })
        let delta = counter.update(with: names.map { InterfaceReading(name: $0, receivedBytes: 9_999, sentBytes: 9_999) })
        XCTAssertEqual(delta, TrafficCounter.Delta(received: 0, sent: 0))
    }

    func testInterfaceAppearingLaterIsBaselinedFirst() {
        var counter = TrafficCounter()
        _ = counter.update(with: [InterfaceReading(name: "en0", receivedBytes: 0, sentBytes: 0)])
        // 中途连上蜂窝：它已有的 8 GB 历史流量不能算进这一秒
        let delta = counter.update(with: [
            InterfaceReading(name: "en0", receivedBytes: 100, sentBytes: 0),
            InterfaceReading(name: "pdp_ip1", receivedBytes: 4_000_000_000, sentBytes: 0),
        ])
        XCTAssertEqual(delta.received, 100)
    }
}
