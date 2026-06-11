import XCTest
@testable import AnchorCore

final class StateReducerTests: XCTestCase {

    let reducer = StateReducer(driftThreshold: 60, slackingDuration: 300)

    private func greenClassifier(_ ctx: AppContext) -> ZoneClassification { .green }
    private func grayClassifier(_ ctx: AppContext) -> ZoneClassification { .gray }
    private func redClassifier(_ ctx: AppContext) -> ZoneClassification { .red }

    // MARK: - app activation transitions

    func testOfflineToGreenOnAppActivated() {
        let ctx = AppContext(bundleId: "com.apple.Xcode")
        let (state, _) = reducer.reduce(.offline, event: .appActivated(ctx), classifier: greenClassifier)
        XCTAssertEqual(state, .green(currentApp: ctx))
    }

    func testGreenToDriftingWhenEnteringGray() {
        let greenCtx = AppContext(bundleId: "com.apple.Xcode")
        let grayCtx = AppContext(bundleId: "com.apple.iCal")
        let (state, _) = reducer.reduce(
            .green(currentApp: greenCtx),
            event: .appActivated(grayCtx),
            classifier: grayClassifier
        )
        XCTAssertEqual(state, .drifting(elapsed: 0, currentApp: grayCtx))
    }

    func testGreenToRedTriggersImmediateFriction() {
        let greenCtx = AppContext(bundleId: "com.apple.Xcode")
        let redCtx = AppContext(bundleId: "com.google.Chrome",
                                url: URL(string: "https://twitter.com/home"))
        let (state, effects) = reducer.reduce(
            .green(currentApp: greenCtx),
            event: .appActivated(redCtx),
            classifier: redClassifier
        )
        XCTAssertEqual(state, .red(currentApp: redCtx))
        XCTAssertEqual(effects, [.renderFriction(level: 0.5)])
    }

    // MARK: - drift tick & friction curve

    func testDriftTickIncrementsElapsedAndAppliesFrictionCurve() {
        let ctx = AppContext(bundleId: "com.apple.iCal")
        var state: AnchorState = .drifting(elapsed: 25, currentApp: ctx)

        // 25 + 10 = 35s → level 0.1
        let result1 = reducer.reduce(state, event: .tick(deltaSeconds: 10), classifier: grayClassifier)
        XCTAssertEqual(result1.0, .drifting(elapsed: 35, currentApp: ctx))
        XCTAssertEqual(result1.1, [.renderFriction(level: 0.1)])

        // 35 + 30 = 65s → level 0.4
        state = result1.0
        let result2 = reducer.reduce(state, event: .tick(deltaSeconds: 30), classifier: grayClassifier)
        if case .drifting(let elapsed, _) = result2.0 {
            XCTAssertEqual(elapsed, 65, accuracy: 0.01)
        } else {
            XCTFail("expected drifting state")
        }
        XCTAssertEqual(result2.1, [.renderFriction(level: 0.4)])
    }

    // MARK: - gestures

    func testTapTriggersSnapBack() {
        let (state, effects) = reducer.reduce(
            .drifting(elapsed: 10, currentApp: AppContext(bundleId: "x")),
            event: .islandTapped,
            classifier: grayClassifier
        )
        XCTAssertEqual(effects, [.snapBackToGreen, .playHaptic(.generic), .clearFriction])
        // state shouldn't pre-emptively change — actual snap-back done by SideEffect handler
        XCTAssertEqual(state, .drifting(elapsed: 10, currentApp: AppContext(bundleId: "x")))
    }

    func testLongPressEntersSlacking() {
        let (state, effects) = reducer.reduce(
            .red(currentApp: AppContext(bundleId: "x")),
            event: .islandLongPressed,
            classifier: redClassifier
        )
        XCTAssertEqual(state, .slacking(remaining: 300))
        XCTAssertEqual(effects, [.clearFriction, .playHaptic(.alignment)])
    }

    func testSlackingCountsDownAndExitsAtZero() {
        var state: AnchorState = .slacking(remaining: 5)
        let result = reducer.reduce(state, event: .tick(deltaSeconds: 5), classifier: greenClassifier)
        XCTAssertEqual(result.0, .offline)
        XCTAssertTrue(result.1.contains(.snapBackToGreen))
    }
}
