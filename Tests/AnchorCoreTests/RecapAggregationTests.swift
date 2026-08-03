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

    /// 文案库存的是**本地化 key**，不是译文——名次按 `index % count` 取梗，
    /// 所以库的长度是有语义的：某个语言多写/少写一条，每个名次拿到的梗就会错位。
    /// 这条断言就是拦住"顺手改一下条数"。
    func testSnarkLibraryIsAFixedLengthKeyList() {
        XCTAssertEqual(TopThieves.snarkLibrary.count, 6)
        for (index, key) in TopThieves.snarkLibrary.enumerated() {
            XCTAssertEqual(key, "thief.snark.\(index)")
        }
        XCTAssertEqual(Set(TopThieves.snarkLibrary).count, TopThieves.snarkLibrary.count)
    }

    /// 查表推迟到渲染：`snark` 是 key，`localizedSnark` 才是给人看的。
    /// 测试里查不到表，`L()` 回落到 key，所以两者相等——但严肃模式下都得是 nil。
    func testLocalizedSnarkResolvesAtRenderTime() {
        let drifts = [drift(to: "a", seconds: 300)]
        let teasing = TopThieves.compute(drifts: drifts, deepScore: 80).first
        XCTAssertEqual(teasing?.localizedSnark, L(TopThieves.snarkLibrary[0]))
        let serious = TopThieves.compute(drifts: drifts, deepScore: 80, seriousMode: true).first
        XCTAssertNil(serious?.localizedSnark)
    }

    /// 六条梗在两种语言里都必须有译文。少一条不会报错，只会在界面上显示成
    /// `thief.snark.4` 这种字符串——所以这里把"少一条"变成硬失败。
    func testEverySnarkKeyHasTextInBothLanguages() throws {
        for language in ["en", "zh-Hans"] {
            try LocalizedTable.withLanguage(language) {
                for key in TopThieves.snarkLibrary {
                    let text = L(key)
                    XCTAssertNotEqual(text, key, "\(language) 缺少 \(key)")
                    XCTAssertFalse(text.isEmpty, "\(language) 的 \(key) 是空串")
                }
            }
        }
    }

    /// 真实表下的成品：名次 → 梗的对应关系不能因为语言而变。
    func testSnarkFollowsRankNotLanguage() throws {
        let drifts = [drift(to: "a", seconds: 300), drift(to: "b", seconds: 200)]
        try LocalizedTable.withLanguage("zh-Hans") {
            let thieves = TopThieves.compute(drifts: drifts, deepScore: 80)
            XCTAssertEqual(thieves[0].localizedSnark, "又赢了")
            XCTAssertEqual(thieves[1].localizedSnark, "假装在学习")
        }
        try LocalizedTable.withLanguage("en") {
            let thieves = TopThieves.compute(drifts: drifts, deepScore: 80)
            XCTAssertEqual(thieves[0].localizedSnark, "undefeated")
            XCTAssertEqual(thieves[1].localizedSnark, "research, technically")
        }
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
