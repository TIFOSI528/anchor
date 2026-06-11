import XCTest
@testable import AnchorCore

final class StatusLabelTests: XCTestCase {

    private let app = AppContext(bundleId: "com.example.app")

    func testGreenLabel() {
        XCTAssertEqual(StatusLabel.text(for: .green(currentApp: app)), "绿区")
    }

    func testRedLabel() {
        XCTAssertEqual(StatusLabel.text(for: .red(currentApp: app)), "红区")
    }

    func testOfflineLabel() {
        XCTAssertEqual(StatusLabel.text(for: .offline), "待命")
    }

    func testPausedLabel() {
        XCTAssertEqual(StatusLabel.text(for: .paused(reason: "lunch")), "已暂停")
    }

    func testDriftingFormatsAsMinutesSeconds() {
        XCTAssertEqual(StatusLabel.text(for: .drifting(elapsed: 30, currentApp: app)), "漂移 0:30")
        XCTAssertEqual(StatusLabel.text(for: .drifting(elapsed: 90, currentApp: app)), "漂移 1:30")
        XCTAssertEqual(StatusLabel.text(for: .drifting(elapsed: 0, currentApp: app)), "漂移 0:00")
    }

    func testSlackingFormatsAsMinutesSeconds() {
        XCTAssertEqual(StatusLabel.text(for: .slacking(remaining: 300)), "摸鱼 5:00")
        XCTAssertEqual(StatusLabel.text(for: .slacking(remaining: 5)), "摸鱼 0:05")
    }

    func testNegativeElapsedClampsToZero() {
        XCTAssertEqual(StatusLabel.text(for: .drifting(elapsed: -10, currentApp: app)), "漂移 0:00")
    }
}
