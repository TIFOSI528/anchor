import XCTest
@testable import AnchorCore

/// `message` / `rationale` 现在走 `L()`。测试里查不到表，`L()` 回落到 key 且参数被
/// `String(format:)` 丢掉——所以对"文案里有没有 6"断言已经不可能，改成对 key 断言。
///
/// 断言的重点也因此更准：这个引擎真正的逻辑是**哪条规则命中、作用在哪个 target 上**，
/// 那两件事完全与语言无关。
final class SuggestionEngineTests: XCTestCase {

    /// 时段的聚合 key。故意用 `windowKey` 生成而不是手写字面量：
    /// 它是字典 key，不是展示文案，两者已经分开（`windowDisplayLabel` 才给人看）。
    private let afternoonWindow = WeeklyAggregator.windowKey(startHour: 14)

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
        let input = WeeklyInput(presetName: "写代码", highDriftWindowConsecutiveDays: [afternoonWindow: 4])
        let suggestion = SuggestionEngine.weeklySuggestion(input)
        XCTAssertEqual(suggestion?.kind, .rhythm)
        XCTAssertEqual(suggestion?.target, afternoonWindow)
    }

    func testNoRuleMatchesReturnsNil() {
        let input = WeeklyInput(
            presetName: "写代码",
            driftTop5Days: ["x.com": 2],
            greenAppWeeklyDriftCount: ["com.slack": 3],
            highDriftWindowConsecutiveDays: [afternoonWindow: 1]
        )
        XCTAssertNil(SuggestionEngine.weeklySuggestion(input))
    }

    /// 可解释性：每条建议都带一条**独立的** rationale key（不是复用 message 的），
    /// 并且真实表下依据里必须带上那个数字——原来的 `contains("6")` 一条没少。
    func testRationaleIsExplainable() throws {
        let input = WeeklyInput(presetName: "写代码", driftTop5Days: ["x.com": 6])
        let suggestion = SuggestionEngine.weeklySuggestion(input)
        XCTAssertEqual(suggestion?.rationale, "suggestion.blacklist.rationale")
        XCTAssertNotEqual(suggestion?.rationale, suggestion?.message)

        for language in ["en", "zh-Hans"] {
            try LocalizedTable.withLanguage(language) {
                let localized = SuggestionEngine.weeklySuggestion(input)
                XCTAssertTrue(localized?.rationale.contains("6") ?? false, "\(language): \(localized?.rationale ?? "nil")")
                // 目标和场景名都得进正文，否则建议没法读懂。
                XCTAssertTrue(localized?.message.contains("x.com") ?? false)
                XCTAssertTrue(localized?.message.contains("写代码") ?? false)
            }
        }
    }

    /// 三条规则各用自己的一套 key，不许串台。
    func testEachRuleUsesItsOwnStringKeys() {
        let blacklist = SuggestionEngine.weeklySuggestion(
            WeeklyInput(presetName: "写代码", driftTop5Days: ["x.com": 6])
        )
        let presetAdjust = SuggestionEngine.weeklySuggestion(
            WeeklyInput(presetName: "写代码", greenAppWeeklyDriftCount: ["com.slack": 21])
        )
        let rhythm = SuggestionEngine.weeklySuggestion(
            WeeklyInput(presetName: "写代码", highDriftWindowConsecutiveDays: [afternoonWindow: 4])
        )
        XCTAssertEqual(blacklist?.message, "suggestion.blacklist.message")
        XCTAssertEqual(presetAdjust?.message, "suggestion.preset_adjust.message")
        XCTAssertEqual(rhythm?.message, "suggestion.rhythm.message")
        XCTAssertEqual(Set([blacklist?.rationale, presetAdjust?.rationale, rhythm?.rationale]).count, 3)
    }

    /// 规则 C 的 `target` 是聚合 key，文案里用的是**另一个**串（显示文案）。
    /// 这两件事分开正是重点：别让本地化过的串变成字典 key。
    func testWindowKeyIsNotTheSameStringAsItsDisplayLabel() throws {
        // 聚合 key：格式钉死、带前导零、与语言无关。
        XCTAssertEqual(afternoonWindow, "14:00–16:00")
        XCTAssertEqual(WeeklyAggregator.windowKey(startHour: 8), "08:00–10:00")
        // 展示文案整串来自 .strings，可以按语言改写；这里连前导零都不一样。
        try LocalizedTable.withLanguage("en") {
            XCTAssertEqual(WeeklyAggregator.windowDisplayLabel(forKey: "08:00–10:00"), "8:00–10:00")
            let rhythm = SuggestionEngine.weeklySuggestion(
                WeeklyInput(presetName: "写代码", highDriftWindowConsecutiveDays: ["08:00–10:00": 4])
            )
            // target 仍是聚合 key，正文里是显示文案：带前导零的那个串不该出现在文案里。
            XCTAssertEqual(rhythm?.target, "08:00–10:00")
            XCTAssertTrue(rhythm?.message.contains("8:00–10:00") ?? false, rhythm?.message ?? "nil")
            XCTAssertFalse(rhythm?.message.contains("08:00") ?? true, rhythm?.message ?? "nil")
        }
        // 解析不出小时时原样返回，不会显示成空白。
        XCTAssertEqual(WeeklyAggregator.windowDisplayLabel(forKey: "no-hours-here"), "no-hours-here")
    }
}
