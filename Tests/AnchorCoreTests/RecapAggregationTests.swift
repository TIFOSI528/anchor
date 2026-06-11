import XCTest
@testable import AnchorCore

private let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

private func drift(
    to app: String,
    url: String? = nil,
    seconds: Int? = nil,
    from: String? = nil,
    next: String? = nil,
    at when: Date = fixedDate
) -> DriftRecord {
    DriftRecord(
        id: "\(app)-\(seconds ?? 0)-\(when.timeIntervalSince1970)",
        sessionId: "s",
        occurredAt: when,
        fromApp: from,
        toApp: app,
        toURL: url,
        durationSeconds: seconds,
        nextDestination: next
    )
}

final class TopThievesTests: XCTestCase {

    func testRanksByDurationDescending() {
        let drifts = [
            drift(to: "com.a", seconds: 100),
            drift(to: "com.b", seconds: 300),
            drift(to: "com.a", seconds: 50)
        ]
        let thieves = TopThieves.compute(drifts: drifts, deepScore: 80)
        XCTAssertEqual(thieves.map(\.label), ["com.b", "com.a"])
        XCTAssertEqual(thieves.map(\.totalSeconds), [300, 150])
        XCTAssertEqual(thieves.map(\.rank), [1, 2])
    }

    func testRespectsLimit() {
        let drifts = (0..<5).map { drift(to: "app\($0)", seconds: 10 * (5 - $0)) }
        XCTAssertEqual(TopThieves.compute(drifts: drifts, deepScore: 80, limit: 3).count, 3)
    }

    func testSeriousModeOmitsSnark() {
        let thieves = TopThieves.compute(drifts: [drift(to: "x", seconds: 60)], deepScore: 80, seriousMode: true)
        XCTAssertNil(thieves.first?.snark)
    }

    func testAutoSeriousWhenScoreBelow30() {
        let thieves = TopThieves.compute(drifts: [drift(to: "x", seconds: 60)], deepScore: 29)
        XCTAssertNil(thieves.first?.snark)
    }

    func testSnarkAssignedByRankWhenNotSerious() {
        let drifts = [drift(to: "a", seconds: 300), drift(to: "b", seconds: 200)]
        let thieves = TopThieves.compute(drifts: drifts, deepScore: 80)
        XCTAssertEqual(thieves[0].snark, TopThieves.snarkLibrary[0])
        XCTAssertEqual(thieves[1].snark, TopThieves.snarkLibrary[1])
    }

    func testEmptyReturnsEmpty() {
        XCTAssertTrue(TopThieves.compute(drifts: [], deepScore: 80).isEmpty)
    }

    func testURLHostUsedAsLabel() {
        let thieves = TopThieves.compute(
            drifts: [drift(to: "com.google.Chrome", url: "https://x.com/home", seconds: 200)],
            deepScore: 80
        )
        XCTAssertEqual(thieves.first?.label, "x.com")
    }
}

final class DriftHeatmapTests: XCTestCase {

    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func at(_ y: Int, _ mo: Int, _ d: Int, _ h: Int) -> Date {
        utc.date(from: DateComponents(year: y, month: mo, day: d, hour: h))!
    }

    func testBucketsDriftsByWeekdayAndHour() {
        // 2024-06-03 is a Monday.
        let drifts = [
            drift(to: "a", at: at(2024, 6, 3, 9)),  // Mon 09:00 → row 0, bucket 0
            drift(to: "a", at: at(2024, 6, 3, 9)),  // again → 2
            drift(to: "a", at: at(2024, 6, 3, 15)), // Mon 15:00 → row 0, bucket 3
            drift(to: "a", at: at(2024, 6, 8, 10)), // Saturday → ignored
            drift(to: "a", at: at(2024, 6, 3, 6))   // before 08:00 → ignored
        ]
        let heatmap = DriftHeatmap.build(drifts: drifts, calendar: utc)
        XCTAssertEqual(heatmap.count(weekday: 0, bucket: 0), 2)
        XCTAssertEqual(heatmap.count(weekday: 0, bucket: 3), 1)
        XCTAssertEqual(heatmap.total, 3)
    }

    func testGridShape() {
        let heatmap = DriftHeatmap.build(drifts: [], calendar: utc)
        XCTAssertEqual(heatmap.grid.count, DriftHeatmap.weekdayCount)
        XCTAssertEqual(heatmap.grid.first?.count, DriftHeatmap.bucketCount)
        XCTAssertEqual(heatmap.total, 0)
    }
}

final class DriftChainsTests: XCTestCase {

    func testTopChainAggregatesCountAndAverage() {
        let drifts = [
            drift(to: "mid", seconds: 100, from: "start", next: "end"),
            drift(to: "mid", seconds: 200, from: "start", next: "end"),
            drift(to: "x", seconds: 60, from: "y", next: "z")
        ]
        let chains = DriftChains.topChains(drifts: drifts)
        XCTAssertEqual(chains.first?.nodes, ["start", "mid", "end"])
        XCTAssertEqual(chains.first?.count, 2)
        XCTAssertEqual(chains.first?.averageSeconds, 150)
        XCTAssertEqual(chains.count, 2)
    }

    func testIncompleteChainsAreSkipped() {
        let chains = DriftChains.topChains(drifts: [drift(to: "mid", from: "start", next: nil)])
        XCTAssertTrue(chains.isEmpty)
    }
}

final class RecapTimelineTests: XCTestCase {

    func testGreenIntervalUpgradesToDeepGreenWhenLongEnough() {
        let intervals = [
            ZoneInterval(start: fixedDate, end: fixedDate.addingTimeInterval(1000), zone: .green),
            ZoneInterval(start: fixedDate.addingTimeInterval(1000), end: fixedDate.addingTimeInterval(1300), zone: .green)
        ]
        XCTAssertEqual(RecapTimeline.segments(from: intervals).map(\.zone), [.deepGreen, .green])
    }

    func testTotalsSumZonesAndTrackLongestStreak() {
        let t = fixedDate
        let intervals = [
            ZoneInterval(start: t, end: t.addingTimeInterval(600), zone: .green),
            ZoneInterval(start: t.addingTimeInterval(600), end: t.addingTimeInterval(900), zone: .gray),
            ZoneInterval(start: t.addingTimeInterval(900), end: t.addingTimeInterval(1000), zone: .red),
            ZoneInterval(start: t.addingTimeInterval(1000), end: t.addingTimeInterval(2000), zone: .green)
        ]
        let totals = RecapTimeline.totals(from: intervals)
        XCTAssertEqual(totals.greenSeconds, 1600)
        XCTAssertEqual(totals.graySeconds, 300)
        XCTAssertEqual(totals.redSeconds, 100)
        XCTAssertEqual(totals.longestStreakSeconds, 1000)
    }
}
