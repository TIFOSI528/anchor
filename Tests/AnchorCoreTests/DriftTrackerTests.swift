import XCTest
@testable import AnchorCore

final class FrictionLevelTests: XCTestCase {

    func testForElapsedBoundaries() {
        XCTAssertEqual(FrictionLevel.forElapsed(0), .none)
        XCTAssertEqual(FrictionLevel.forElapsed(29.9), .none)
        XCTAssertEqual(FrictionLevel.forElapsed(30), .subtle)
        XCTAssertEqual(FrictionLevel.forElapsed(59.9), .subtle)
        XCTAssertEqual(FrictionLevel.forElapsed(60), .moderate)
        XCTAssertEqual(FrictionLevel.forElapsed(179.9), .moderate)
        XCTAssertEqual(FrictionLevel.forElapsed(180), .heavy)
        XCTAssertEqual(FrictionLevel.forElapsed(3600), .heavy)
    }

    func testBlurIntensityMatchesReducerCurve() {
        XCTAssertEqual(FrictionLevel.none.blurIntensity, 0.0)
        XCTAssertEqual(FrictionLevel.subtle.blurIntensity, 0.1)
        XCTAssertEqual(FrictionLevel.moderate.blurIntensity, 0.4)
        XCTAssertEqual(FrictionLevel.heavy.blurIntensity, 0.8)
    }

    func testComparable() {
        XCTAssertLessThan(FrictionLevel.none, FrictionLevel.heavy)
        XCTAssertGreaterThan(FrictionLevel.moderate, FrictionLevel.subtle)
    }
}

final class DriftTrackerTests: XCTestCase {

    func testTickAccumulatesElapsed() {
        let tracker = DriftTracker()
        tracker.tick(10)
        tracker.tick(15)
        XCTAssertEqual(tracker.elapsed, 25, accuracy: 0.001)
    }

    func testTickReturnsLevelAtCurrentElapsed() {
        let tracker = DriftTracker()
        XCTAssertEqual(tracker.tick(35), .subtle)
        XCTAssertEqual(tracker.tick(30), .moderate) // 65s
        XCTAssertEqual(tracker.tick(140), .heavy)   // 205s
    }

    func testResetZeroes() {
        let tracker = DriftTracker(elapsed: 120)
        XCTAssertEqual(tracker.level, .moderate)
        tracker.reset()
        XCTAssertEqual(tracker.elapsed, 0)
        XCTAssertEqual(tracker.level, .none)
    }

    func testNegativeDeltaClampedToZero() {
        let tracker = DriftTracker(elapsed: 10)
        tracker.tick(-100)
        XCTAssertEqual(tracker.elapsed, 10, accuracy: 0.001)
    }
}
