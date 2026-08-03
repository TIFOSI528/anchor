import XCTest
@testable import AnchorCore

/// 叙事文案现在整句进 `.strings`。单元测试里 `L()` 查不到表会回落到 key，
/// 并且 `String(format:)` 会把参数一起丢掉——所以对"文案里有没有 47 分钟"断言已经不可能。
///
/// 改成断言**结构**：走了哪个分支（哪个 key 进了正文）、哪个分支被正确省略。
/// 分支选择才是这个类真正的逻辑；数字与单位的拼法交给 `DurationLabel` 单独测。
/// 好处是断言彻底与语言解耦：改中文或英文译文都不会弄红测试。
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
        // 三段都在，且段间是空行分隔。
        XCTAssertEqual(text.components(separatedBy: "\n\n").count, 3)
        // 有起止时间 → 用带区间的那一句，不是 plain。
        XCTAssertTrue(text.contains("narrative.p1.with_streak_range"))
        XCTAssertFalse(text.contains("narrative.p1.plain"))
        // 9/23 ≥ 30% 且连续 5 天 → 走"连续第 N 天"那一整句。
        XCTAssertTrue(text.contains("narrative.p2.top_destination_streak"))
        XCTAssertTrue(text.contains("narrative.p3.hardest_window"))
    }

    /// 138 分钟必须进位成"2 小时 18 分钟"，47 分钟不进位，125 分钟不能读成"125 分钟"。
    /// 单位与进位都是文案的一部分，所以在 `DurationLabel` 这一层验。
    func testDurationLabelCarriesHoursAndMinutes() {
        XCTAssertEqual(DurationLabel.split(totalMinutes: 138).hours, 2)
        XCTAssertEqual(DurationLabel.split(totalMinutes: 138).minutes, 18)
        XCTAssertEqual(DurationLabel.text(minutes: 138), "recap.duration.hours_minutes")
        XCTAssertEqual(DurationLabel.text(minutes: 125), "recap.duration.hours_minutes")
        XCTAssertEqual(DurationLabel.text(minutes: 47), "recap.duration.minutes")
        XCTAssertEqual(DurationLabel.text(minutes: 120), "recap.duration.hours")
        XCTAssertEqual(DurationLabel.text(seconds: 45), "recap.duration.seconds")
        XCTAssertEqual(DurationLabel.text(seconds: -5), "recap.duration.seconds")
    }

    /// 单位是文案的一部分，所以两种语言的成品都要看一眼。
    /// 125 分钟绝不能读成 "125 min"。
    func testDurationLabelWordsUnitsPerLanguage() throws {
        try LocalizedTable.withLanguage("en") {
            XCTAssertEqual(DurationLabel.text(minutes: 125), "2 hr 5 min")
            XCTAssertEqual(DurationLabel.text(minutes: 47), "47 min")
            XCTAssertEqual(DurationLabel.text(minutes: 120), "2 hr")
            XCTAssertEqual(DurationLabel.text(seconds: 45), "45 sec")
        }
        try LocalizedTable.withLanguage("zh-Hans") {
            XCTAssertEqual(DurationLabel.text(minutes: 125), "2 小时 5 分钟")
            XCTAssertEqual(DurationLabel.text(seconds: 45), "45 秒")
        }
    }

    /// 真实表下的完整输出。原来那六条断言（"2 小时 18 分钟" / "47 分钟" / 场景名 /
    /// 目的地 / "连续第 5 天" / 时段）一条没少，只是现在**显式指定语言**，
    /// 并且英文一起验：位置说明符写错、或哪个分支漏了参数，都会在这里露出来。
    func testRealTableFillsInEveryArgument() throws {
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
        try LocalizedTable.withLanguage("zh-Hans") {
            let text = gen.generate(input: input)
            XCTAssertTrue(text.contains("2 小时 18 分钟"), text)
            XCTAssertTrue(text.contains("47 分钟"), text)
            XCTAssertTrue(text.contains("写代码"), text)
            XCTAssertTrue(text.contains("11:03–11:50"), text)
            XCTAssertTrue(text.contains("GitHub trending"), text)
            XCTAssertTrue(text.contains("连续第 5 天"), text)
            XCTAssertTrue(text.contains("14:00–16:00"), text)
        }
        try LocalizedTable.withLanguage("en") {
            let text = gen.generate(input: input)
            XCTAssertTrue(text.contains("2 hr 18 min"), text)
            XCTAssertTrue(text.contains("47 min"), text)
            XCTAssertTrue(text.contains("写代码"), text)   // 场景名是输入，原样透传
            XCTAssertTrue(text.contains("GitHub trending"), text)
            XCTAssertTrue(text.contains("day 5 in a row"), text)
            XCTAssertTrue(text.contains("14:00–16:00"), text)
            // 句尾标点必须来自表，不是代码拼上去的——中文标点漏进英文就是那个 bug 的信号。
            XCTAssertFalse(text.contains("。"), text)
            XCTAssertFalse(text.contains("——"), text)
        }
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
        XCTAssertFalse(text.contains("narrative.p2."))
        // 没有起止时间 → plain 版本。
        XCTAssertTrue(text.contains("narrative.p1.plain"))
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
        XCTAssertTrue(text.contains("narrative.p2.scattered"))
        XCTAssertFalse(text.contains("narrative.p2.top_destination"))
    }

    /// 突出目的地但不连续 → 用不带"连续第 N 天"的那一句。
    /// 原来这里是 `line += "。"` vs `line += " —— 连续第 N 天了。"`，现在是两个独立的整句。
    func testDominantDestinationWithoutStreakUsesPlainSentence() {
        let input = NarrativeGenerator.Input(
            deepMinutes: 100,
            longestStreakMinutes: 30,
            presetName: "写代码",
            driftCount: 10,
            topDestination: "x.com",
            topDestinationCount: 6,
            consecutiveDaysWithSameTopDest: 1
        )
        let text = gen.generate(input: input)
        XCTAssertTrue(text.contains("narrative.p2.top_destination"))
        XCTAssertFalse(text.contains("narrative.p2.top_destination_streak"))
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
        XCTAssertFalse(text.contains("narrative.p3."))
    }
}
