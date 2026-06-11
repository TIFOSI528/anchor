import XCTest
@testable import AnchorCore

final class DeepScoreTests: XCTestCase {

    let scorer = DeepScore()

    func testPureGreenSessionGetsMaxScore() {
        let input = DeepScore.Input(
            greenMinutes: 240,
            grayMinutes: 0,
            redMinutes: 0,
            driftCount: 0
        )
        XCTAssertEqual(scorer.compute(input: input), 100)
    }

    func testPureRedSessionGetsZero() {
        let input = DeepScore.Input(
            greenMinutes: 0,
            grayMinutes: 0,
            redMinutes: 120,
            driftCount: 0
        )
        XCTAssertEqual(scorer.compute(input: input), 0)
    }

    func testMixedDayMatchesNarrativeExample() {
        // Reproduces the narrative example used in the daily-recap mockup:
        // 138 min deep work, 23 drifts, some gray and red.
        let input = DeepScore.Input(
            greenMinutes: 138,
            grayMinutes: 60,
            redMinutes: 25,
            driftCount: 23
        )
        let score = scorer.compute(input: input)
        // Per the §III formula this mixed day normalizes to ~47: above the
        // serious-mode threshold (30) yet well short of a clean green day. We assert
        // the band, not an exact value — the formula is the spec, the score is derived.
        XCTAssertGreaterThan(score, 30)
        XCTAssertLessThan(score, 70)
    }

    func testEmptyDayGetsZero() {
        let input = DeepScore.Input(
            greenMinutes: 0, grayMinutes: 0, redMinutes: 0, driftCount: 0
        )
        XCTAssertEqual(scorer.compute(input: input), 0)
    }

    func testDriftCountPenaltyApplies() {
        let baseline = DeepScore.Input(
            greenMinutes: 120, grayMinutes: 0, redMinutes: 0, driftCount: 0
        )
        let withDrifts = DeepScore.Input(
            greenMinutes: 120, grayMinutes: 0, redMinutes: 0, driftCount: 30
        )
        XCTAssertGreaterThan(scorer.compute(input: baseline), scorer.compute(input: withDrifts))
    }
}
