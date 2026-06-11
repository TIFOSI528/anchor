import XCTest
@testable import AnchorCore

final class SuggestionEngineTests: XCTestCase {

    func testRuleABlacklistFiresAboveThreshold() {
        let input = WeeklyInput(presetName: "写代码", driftTop5Days: ["x.com": 6])
        let suggestion = SuggestionEngine.weeklySuggestion(input)
        XCTAssertEqual(suggestion?.kind, .blacklist)
        XCTAssertEqual(suggestion?.target, "x.com")
    }

    func testRuleADoesNotFireAtExactThreshold() {
        // threshold is strictly greater-than 5
        let input = WeeklyInput(presetName: "写代码", driftTop5Days: ["x.com": 5])
        XCTAssertNil(SuggestionEngine.weeklySuggestion(input))
    }

    func testRuleAPicksStrongestTarget() {
        let input = WeeklyInput(presetName: "写代码", driftTop5Days: ["a": 6, "b": 9, "c": 7])
        XCTAssertEqual(SuggestionEngine.weeklySuggestion(input)?.target, "b")
    }

    func testPriorityABeatsB() {
        let input = WeeklyInput(
            presetName: "写代码",
            driftTop5Days: ["x.com": 6],
            greenAppWeeklyDriftCount: ["com.slack": 50]
        )
        XCTAssertEqual(SuggestionEngine.weeklySuggestion(input)?.kind, .blacklist)
    }

    func testRuleBPresetAdjustFires() {
        let input = WeeklyInput(presetName: "写代码", greenAppWeeklyDriftCount: ["com.slack": 21])
        let suggestion = SuggestionEngine.weeklySuggestion(input)
        XCTAssertEqual(suggestion?.kind, .presetAdjust)
        XCTAssertEqual(suggestion?.target, "com.slack")
    }

    func testRuleCRhythmFiresAtThreshold() {
        let input = WeeklyInput(presetName: "写代码", highDriftWindowConsecutiveDays: ["14:00–16:00": 4])
        let suggestion = SuggestionEngine.weeklySuggestion(input)
        XCTAssertEqual(suggestion?.kind, .rhythm)
        XCTAssertEqual(suggestion?.target, "14:00–16:00")
    }

    func testNoRuleMatchesReturnsNil() {
        let input = WeeklyInput(
            presetName: "写代码",
            driftTop5Days: ["x.com": 2],
            greenAppWeeklyDriftCount: ["com.slack": 3],
            highDriftWindowConsecutiveDays: ["14:00–16:00": 1]
        )
        XCTAssertNil(SuggestionEngine.weeklySuggestion(input))
    }

    func testRationaleIsExplainable() {
        let input = WeeklyInput(presetName: "写代码", driftTop5Days: ["x.com": 6])
        XCTAssertTrue(SuggestionEngine.weeklySuggestion(input)?.rationale.contains("6") ?? false)
    }
}
