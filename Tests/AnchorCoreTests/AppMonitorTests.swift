import XCTest
@testable import AnchorCore

final class AppMonitorTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_000)
    private let t1 = Date(timeIntervalSince1970: 1_005)
    private let t2 = Date(timeIntervalSince1970: 1_012)

    func testFirstActivationEmitsEvent() {
        let monitor = AppMonitor()
        guard case let .appActivated(ctx)? = monitor.record(bundleId: "com.apple.Terminal", at: t0) else {
            return XCTFail("expected an appActivated event")
        }
        XCTAssertEqual(ctx, AppContext(bundleId: "com.apple.Terminal"))
        XCTAssertEqual(monitor.current, AppContext(bundleId: "com.apple.Terminal"))
        XCTAssertEqual(monitor.lastChangeAt, t0)
    }

    func testConsecutiveSameAppIsDeduped() {
        let monitor = AppMonitor()
        XCTAssertNotNil(monitor.record(bundleId: "com.apple.Terminal", at: t0))
        XCTAssertNil(monitor.record(bundleId: "com.apple.Terminal", at: t1))
        // dedup must not advance the change timestamp
        XCTAssertEqual(monitor.lastChangeAt, t0)
    }

    func testDifferentAppEmitsAndAdvancesTimestamp() {
        let monitor = AppMonitor()
        _ = monitor.record(bundleId: "com.apple.Terminal", at: t0)
        guard case let .appActivated(ctx)? = monitor.record(bundleId: "com.microsoft.VSCode", at: t1) else {
            return XCTFail("expected an appActivated event on app switch")
        }
        XCTAssertEqual(ctx, AppContext(bundleId: "com.microsoft.VSCode"))
        XCTAssertEqual(monitor.lastChangeAt, t1)
    }

    func testURLChangeOnSameBundleEmits() {
        let monitor = AppMonitor()
        let github = URL(string: "https://github.com/anchor")!
        let twitter = URL(string: "https://x.com/home")!
        XCTAssertNotNil(monitor.record(bundleId: "com.google.Chrome", url: github, at: t0))
        // same browser, different tab → still a meaningful change
        guard case let .appActivated(ctx)? = monitor.record(bundleId: "com.google.Chrome", url: twitter, at: t1) else {
            return XCTFail("expected an event when the active tab URL changes")
        }
        XCTAssertEqual(ctx.url, twitter)
    }

    func testMockStreamProducesOneEventPerDistinctContext() {
        let monitor = AppMonitor()
        let stream: [(String, Date)] = [
            ("com.apple.Terminal", t0),
            ("com.apple.Terminal", t1),   // dedup
            ("com.microsoft.VSCode", t1),
            ("com.microsoft.VSCode", t2), // dedup
            ("com.apple.Terminal", t2)
        ]
        let events = stream.compactMap { monitor.record(bundleId: $0.0, at: $0.1) }
        XCTAssertEqual(events.count, 3)
    }

    func testResetClearsCurrentSoSameAppReEmits() {
        let monitor = AppMonitor()
        _ = monitor.record(bundleId: "com.apple.Terminal", at: t0)
        monitor.reset()
        XCTAssertNil(monitor.current)
        XCTAssertNil(monitor.lastChangeAt)
        XCTAssertNotNil(monitor.record(bundleId: "com.apple.Terminal", at: t1))
    }
}
