import XCTest
@testable import AnchorCore

final class NarrativeGeneratorTests: XCTestCase {

    let gen = NarrativeGenerator()

    func testGeneratesAllThreeParagraphsWhenDataIsRich() {
        let input = NarrativeGenerator.Input(
            deepMinutes: 138,
            longestStreakMinutes: 47,
            streakStartLabel: "11:03",
            streakEndLabel: "11:50",
            presetName: "写代码",
            driftCount: 23,
            topDestination: "GitHub trending",
            topDestinationCount: 9,
            consecutiveDaysWithSameTopDest: 5,
            hardestTimeWindow: "14:00–16:00",
            hardestWindowDaysOutOf7: 5
        )
        let text = gen.generate(input: input)
        XCTAssertTrue(text.contains("2 小时 18 分钟"))
        XCTAssertTrue(text.contains("47 分钟"))
        XCTAssertTrue(text.contains("写代码"))
        XCTAssertTrue(text.contains("GitHub trending"))
        XCTAssertTrue(text.contains("连续第 5 天"))
        XCTAssertTrue(text.contains("14:00–16:00"))
    }

    func testOmitsParagraph2WhenNoDrifts() {
        let input = NarrativeGenerator.Input(
            deepMinutes: 240,
            longestStreakMinutes: 120,
            streakStartLabel: nil,
            streakEndLabel: nil,
            presetName: "写代码",
            driftCount: 0
        )
        let text = gen.generate(input: input)
        XCTAssertFalse(text.contains("漂出去"))
    }

    func testUsesGenericLineWhenNoDominantDestination() {
        let input = NarrativeGenerator.Input(
            deepMinutes: 100,
            longestStreakMinutes: 30,
            presetName: "读资料",
            driftCount: 20,
            topDestination: "Twitter",
            topDestinationCount: 3, // only 15% of drifts
            consecutiveDaysWithSameTopDest: 0
        )
        let text = gen.generate(input: input)
        XCTAssertTrue(text.contains("无意识切换"))
    }

    func testOmitsParagraph3WhenPatternIsWeak() {
        let input = NarrativeGenerator.Input(
            deepMinutes: 100,
            longestStreakMinutes: 30,
            presetName: "写代码",
            driftCount: 5,
            hardestTimeWindow: "15:00–17:00",
            hardestWindowDaysOutOf7: 1 // only 1 day, not a pattern
        )
        let text = gen.generate(input: input)
        XCTAssertFalse(text.contains("最难稳住"))
    }
}
