import XCTest

final class CPULoadTests: XCTestCase {
    func testUsageFromTickDeltas() throws {
        let old = CPUTicks(user: 100, system: 50, idle: 800, nice: 0)
        let new = CPUTicks(user: 130, system: 60, idle: 860, nice: 0)
        let load = try XCTUnwrap(CPULoad(from: old, to: new))
        // 用户 30 + 系统 10 + 空闲 60 = 100
        XCTAssertEqual(load.usage, 0.4, accuracy: 1e-9)
        XCTAssertEqual(load.user, 0.3, accuracy: 1e-9)
        XCTAssertEqual(load.system, 0.1, accuracy: 1e-9)
    }

    func testNiceCountsAsUser() throws {
        let old = CPUTicks(user: 0, system: 0, idle: 0, nice: 0)
        let new = CPUTicks(user: 10, system: 0, idle: 80, nice: 10)
        let load = try XCTUnwrap(CPULoad(from: old, to: new))
        XCTAssertEqual(load.user, 0.2, accuracy: 1e-9)
    }

    func testTickWrapAround() throws {
        let old = CPUTicks(user: UInt32.max - 9, system: 0, idle: 0, nice: 0)
        let new = CPUTicks(user: 40, system: 0, idle: 50, nice: 0)
        let load = try XCTUnwrap(CPULoad(from: old, to: new))
        // 用户 tick 回绕后增加 50，空闲 50
        XCTAssertEqual(load.usage, 0.5, accuracy: 1e-9)
    }

    func testNoTicksReturnsNil() {
        let ticks = CPUTicks(user: 1, system: 2, idle: 3, nice: 4)
        XCTAssertNil(CPULoad(from: ticks, to: ticks))
    }
}
