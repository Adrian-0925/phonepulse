import XCTest

final class FloatingStyleTests: XCTestCase {
    func testLinesAndSummary() {
        XCTAssertEqual(FloatingStyle.standard.lines, [.download, .upload])
        XCTAssertEqual(FloatingStyle.standard.summary, "下载 / 上传 · 彩色")
        let single = FloatingStyle(firstLine: .battery, secondLine: .none, palette: .white)
        XCTAssertEqual(single.lines, [.battery])
        XCTAssertEqual(single.summary, "电量 · 白色")
    }

    func testSpeedText() {
        let snapshot = MetricsSnapshot.placeholder
        XCTAssertEqual(FloatingStyle.text(for: .download, snapshot: snapshot), "↓ 1.20 MB/s")
        XCTAssertEqual(FloatingStyle.text(for: .upload, snapshot: snapshot), "↑ 85.0 KB/s")
        XCTAssertEqual(FloatingStyle.text(for: .download, snapshot: nil), "↓ 0 B/s")
    }

    func testBatteryTextShowsEstimatedPowerOnlyWhenAvailable() {
        var snapshot = MetricsSnapshot.placeholder
        // 占位数据：充电中、有速度和容量，按初步估算显示功率
        XCTAssertEqual(FloatingStyle.text(for: .battery, snapshot: snapshot), "⚡ 76% ≈ 15 W")

        // 还在采集：只显示电量
        snapshot.battery.levelPerHour = nil
        snapshot.battery.estimatedPowerWatts = nil
        XCTAssertEqual(FloatingStyle.text(for: .battery, snapshot: snapshot), "⚡ 76%")

        snapshot.battery.state = .unplugged
        XCTAssertEqual(FloatingStyle.text(for: .battery, snapshot: snapshot), "电量 76%")

        snapshot.battery.level = nil
        XCTAssertEqual(FloatingStyle.text(for: .battery, snapshot: snapshot), "电量 --")
    }

    func testCPUText() {
        XCTAssertTrue(FloatingStyle.text(for: .cpu, snapshot: .placeholder).hasPrefix("CPU 23"))
        XCTAssertEqual(FloatingStyle.text(for: .cpu, snapshot: nil), "CPU --")
    }

    func testSaveAndLoad() throws {
        let suite = "FloatingStyleTests"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(FloatingStyle.load(from: defaults), .standard)
        let style = FloatingStyle(firstLine: .cpu, secondLine: .none, palette: .green)
        style.save(to: defaults)
        XCTAssertEqual(FloatingStyle.load(from: defaults), style)

        // 第一行不能是「不显示」：读到这样的值就回到默认
        defaults.set("none", forKey: "floatingFirstLine")
        XCTAssertEqual(FloatingStyle.load(from: defaults).firstLine, .download)
    }
}
