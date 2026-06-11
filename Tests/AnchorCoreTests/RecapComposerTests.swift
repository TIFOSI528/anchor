import XCTest
@testable import AnchorCore

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

    func testDisplayNameResolverAppliesToPresentationOnly() {
        let session = SessionRecord(id: "s1", presetId: "p", startedAt: at(0), endedAt: at(3600))
        let drifts = [
            DriftRecord(id: "d1", sessionId: "s1", occurredAt: at(600), fromApp: "green.app",
                        toApp: "com.apple.Preview", durationSeconds: 300,
                        endReason: .tap, nextDestination: "com.apple.Preview")
        ]
        let data = RecapComposer.compose(
            dateLabel: "d", presetName: "写代码",
            sessions: [session], todayDrifts: drifts, weekDrifts: drifts,
            classify: { _ in .gray },
            displayName: { $0 == "com.apple.Preview" ? "预览" : $0 },
            now: at(3600)
        )
        XCTAssertEqual(data.thieves.first?.label, "预览")
        XCTAssertEqual(data.chains.first?.nodes, ["green.app", "预览", "预览"])
        XCTAssertTrue(data.narrative.contains("预览"))
        XCTAssertFalse(data.narrative.contains("com.apple.Preview"))
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
