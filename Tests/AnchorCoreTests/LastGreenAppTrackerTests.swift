import XCTest
@testable import AnchorCore

final class LastGreenAppTrackerTests: XCTestCase {

    private func app(_ id: String) -> AppContext { AppContext(bundleId: id) }

    func testRecordPushesMostRecentToFront() {
        let tracker = LastGreenAppTracker()
        tracker.record(app("a"))
        tracker.record(app("b"))
        XCTAssertEqual(tracker.snapBackTarget, app("b"))
        XCTAssertEqual(tracker.apps.map(\.bundleId), ["b", "a"])
    }

    func testReRecordingExistingMovesToFrontWithoutDuplicate() {
        let tracker = LastGreenAppTracker()
        tracker.record(app("a"))
        tracker.record(app("b"))
        tracker.record(app("a"))
        XCTAssertEqual(tracker.apps.map(\.bundleId), ["a", "b"])
    }

    func testCapacityDropsOldest() {
        let tracker = LastGreenAppTracker(capacity: 3)
        ["a", "b", "c", "d"].forEach { tracker.record(app($0)) }
        XCTAssertEqual(tracker.apps.map(\.bundleId), ["d", "c", "b"])
        XCTAssertEqual(tracker.apps.count, 3)
    }

    func testEmptyStackHasNoTarget() {
        let tracker = LastGreenAppTracker()
        XCTAssertNil(tracker.snapBackTarget)
    }

    func testResetClears() {
        let tracker = LastGreenAppTracker()
        tracker.record(app("a"))
        tracker.reset()
        XCTAssertTrue(tracker.apps.isEmpty)
        XCTAssertNil(tracker.snapBackTarget)
    }
}
