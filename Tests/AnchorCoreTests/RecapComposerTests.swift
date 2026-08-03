import XCTest
@testable import AnchorCore

/// 注意 `data.narrative`：叙事整句进 `.strings`，测试里 `L()` 查不到表会回落到 key，
/// 参数（app 名、次数）会被 `String(format:)` 丢掉。所以这里只能对**结构**断言
/// （走了哪一句），displayName 是否真的生效改由 `thieves` / `chains` 两个展示字段验证。
final class RecapComposerTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    func testComposesFullRecapFromOneSession() {
        let session = SessionRecord(id: "s1", presetId: "p", startedAt: at(0), endedAt: at(3600))
        let drifts = [
            DriftRecord(id: "d1", sessionId: "s1", occurredAt: at(600), fromApp: "green.app",
                        toApp: "com.x", toURL: "https://x.com/home", durationSeconds: 300,
                        endReason: .tap, nextDestination: nil)
        ]

        let data = RecapComposer.compose(
            dateLabel: "2026-06-10",
            presetName: "写代码",
            sessions: [session],
            todayDrifts: drifts,
            weekDrifts: drifts,
            classify: { _ in .red },
            now: at(3600)
        )

        // 3600s session - 300s red = 3300s green; longest green run = 2700s
        XCTAssertEqual(data.totals.greenSeconds, 3300)
        XCTAssertEqual(data.totals.redSeconds, 300)
        XCTAssertEqual(data.totals.driftCount, 1)
        XCTAssertEqual(data.totals.longestStreakSeconds, 2700)
        // 600s green (< 900s 阈值，不升级) → 300s red → 2700s deepGreen
        XCTAssertEqual(data.segments.map(\.zone), [.green, .red, .deepGreen])
        XCTAssertEqual(data.thieves.first?.label, "x.com")
        XCTAssertFalse(data.narrative.isEmpty)
        XCTAssertGreaterThan(data.deepScore, 0)
    }

    func testEmptyDayProducesZeroScoreAndEmptySections() {
        let data = RecapComposer.compose(
            dateLabel: "2026-06-10", presetName: "写代码",
            sessions: [], todayDrifts: [], weekDrifts: [],
            classify: { _ in .gray }, now: t0
        )
        XCTAssertEqual(data.deepScore, 0)
        XCTAssertTrue(data.segments.isEmpty)
        XCTAssertTrue(data.thieves.isEmpty)
        XCTAssertEqual(data.totals.onlineSeconds, 0)
    }

    func testDisplayNameResolverAppliesToPresentationOnly() throws {
        let session = SessionRecord(id: "s1", presetId: "p", startedAt: at(0), endedAt: at(3600))
        let drifts = [
            DriftRecord(id: "d1", sessionId: "s1", occurredAt: at(600), fromApp: "green.app",
                        toApp: "com.apple.Preview", durationSeconds: 300,
                        endReason: .tap, nextDestination: "com.apple.Preview")
        ]
        func compose() -> RecapData {
            RecapComposer.compose(
                dateLabel: "d", presetName: "写代码",
                sessions: [session], todayDrifts: drifts, weekDrifts: drifts,
                classify: { _ in .gray },
                displayName: { $0 == "com.apple.Preview" ? "预览" : $0 },
                now: at(3600)
            )
        }

        let data = compose()
        XCTAssertEqual(data.thieves.first?.label, "预览")
        XCTAssertEqual(data.chains.first?.nodes, ["green.app", "预览", "预览"])
        // topDestination 非空 → 走"有突出去处"那一句（说明 displayName 进了叙事输入）。
        XCTAssertTrue(data.narrative.contains("narrative.p2.top_destination"))

        // 真实表下才能看到参数被填进句子：友好名字要出现、原始 bundleId 永远不许出现。
        for language in ["zh-Hans", "en"] {
            try LocalizedTable.withLanguage(language) {
                let localized = compose()
                XCTAssertTrue(localized.narrative.contains("预览"), "\(language): \(localized.narrative)")
                XCTAssertFalse(localized.narrative.contains("com.apple.Preview"), language)
            }
        }
    }

    func testOngoingSessionUsesNowAsEnd() {
        let session = SessionRecord(id: "s1", presetId: "p", startedAt: at(0), endedAt: nil)
        let data = RecapComposer.compose(
            dateLabel: "d", presetName: "p",
            sessions: [session], todayDrifts: [], weekDrifts: [],
            classify: { _ in .gray }, now: at(120)
        )
        XCTAssertEqual(data.totals.greenSeconds, 120)
    }
}
