import XCTest
@testable import AnchorCore

private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

final class BrowserTabRegistryTests: XCTestCase {

    func testEnrichAttachesActiveTabURLToKnownBrowser() {
        let registry = BrowserTabRegistry()
        let url = URL(string: "https://x.com/home")!
        registry.recordActiveTab(browser: "chrome", url: url)
        let enriched = registry.enrich(AppContext(bundleId: "com.google.Chrome"))
        XCTAssertEqual(enriched, AppContext(bundleId: "com.google.Chrome", url: url))
    }

    func testEnrichLeavesNonBrowserUntouched() {
        let registry = BrowserTabRegistry()
        registry.recordActiveTab(browser: "chrome", url: URL(string: "https://x.com")!)
        let ctx = AppContext(bundleId: "com.apple.Xcode")
        XCTAssertEqual(registry.enrich(ctx), ctx)
    }

    func testClearRemovesTabState() {
        let registry = BrowserTabRegistry()
        registry.recordActiveTab(browser: "chrome", url: URL(string: "https://x.com")!)
        registry.clear(browser: "chrome")
        let ctx = AppContext(bundleId: "com.google.Chrome")
        XCTAssertEqual(registry.enrich(ctx), ctx)
    }

    func testBrowserNameLookup() {
        let registry = BrowserTabRegistry()
        XCTAssertEqual(registry.browserName(forBundleId: "com.apple.Safari"), "safari")
        XCTAssertNil(registry.browserName(forBundleId: "com.apple.Xcode"))
    }
}

final class TimelineBuilderTests: XCTestCase {

    private func drift(at start: TimeInterval, seconds: Int?, to app: String = "x") -> DriftRecord {
        DriftRecord(id: "d\(start)", sessionId: "s", occurredAt: at(start), toApp: app, durationSeconds: seconds)
    }

    func testGapsBetweenDriftsBecomeGreen() {
        let intervals = TimelineBuilder.intervals(
            sessionStart: at(0),
            sessionEnd: at(1000),
            drifts: [drift(at: 200, seconds: 100), drift(at: 600, seconds: 50)],
            classify: { _ in .gray }
        )
        XCTAssertEqual(intervals.map(\.zone), [.green, .gray, .green, .gray, .green])
        XCTAssertEqual(intervals.map(\.seconds), [200, 100, 300, 50, 350])
    }

    func testOngoingDriftExtendsToSessionEnd() {
        let intervals = TimelineBuilder.intervals(
            sessionStart: at(0), sessionEnd: at(500),
            drifts: [drift(at: 400, seconds: nil)],
            classify: { _ in .red }
        )
        XCTAssertEqual(intervals.last?.zone, .red)
        XCTAssertEqual(intervals.last?.seconds, 100)
    }

    func testNoDriftsIsAllGreen() {
        let intervals = TimelineBuilder.intervals(sessionStart: at(0), sessionEnd: at(60), drifts: [], classify: { _ in .gray })
        XCTAssertEqual(intervals, [ZoneInterval(start: at(0), end: at(60), zone: .green)])
    }

    func testClassifierDecidesGrayVsRed() {
        let intervals = TimelineBuilder.intervals(
            sessionStart: at(0), sessionEnd: at(100),
            drifts: [drift(at: 10, seconds: 10, to: "red.app")],
            classify: { $0.toApp == "red.app" ? .red : .gray }
        )
        XCTAssertEqual(intervals[1].zone, .red)
    }
}

final class WeeklyAggregatorTests: XCTestCase {

    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func drift(day: Int, hour: Int, to app: String, from: String? = nil) -> DriftRecord {
        let date = utc.date(from: DateComponents(year: 2026, month: 6, day: day, hour: hour))!
        return DriftRecord(
            id: UUID().uuidString, sessionId: "s", occurredAt: date,
            fromApp: from, toApp: app, durationSeconds: 30
        )
    }

    func testTop5DaysCountsDaysInTop5() {
        // x.com 在 3 天里都有漂移 → 3 天进 top5
        let drifts = [
            drift(day: 1, hour: 10, to: "x.com"),
            drift(day: 2, hour: 10, to: "x.com"),
            drift(day: 3, hour: 10, to: "x.com"),
            drift(day: 1, hour: 11, to: "other.app")
        ]
        let days = WeeklyAggregator.top5Days(drifts: drifts, calendar: utc)
        XCTAssertEqual(days["x.com"], 3)
        XCTAssertEqual(days["other.app"], 1)
    }

    func testGreenSourceCountsFilterByClosure() {
        let drifts = [
            drift(day: 1, hour: 9, to: "x.com", from: "com.slack"),
            drift(day: 1, hour: 10, to: "x.com", from: "com.slack"),
            drift(day: 1, hour: 11, to: "x.com", from: "not.green")
        ]
        let counts = WeeklyAggregator.greenSourceCounts(drifts: drifts, isGreenSource: { $0 == "com.slack" })
        XCTAssertEqual(counts, ["com.slack": 2])
    }

    func testWindowConsecutiveDaysFindsLongestRun() {
        // 14:00–16:00 时段：day1/2/3 各 3 次（高漂移），day5 也 3 次 → 最长连续 3 天
        var drifts: [DriftRecord] = []
        for day in [1, 2, 3, 5] {
            for _ in 0..<3 { drifts.append(drift(day: day, hour: 14, to: "x.com")) }
        }
        let windows = WeeklyAggregator.windowConsecutiveDays(drifts: drifts, calendar: utc)
        XCTAssertEqual(windows["14:00–16:00"], 3)
    }

    func testBelowThresholdWindowIgnored() {
        let drifts = [drift(day: 1, hour: 14, to: "x.com"), drift(day: 1, hour: 15, to: "x.com")]
        XCTAssertTrue(WeeklyAggregator.windowConsecutiveDays(drifts: drifts, calendar: utc).isEmpty)
    }
}

final class PresetSerializationTests: XCTestCase {

    func testRuleLineRoundTrip() {
        XCTAssertEqual(PresetSerialization.rule(fromLine: "app:com.apple.Xcode"), .app(bundleId: "com.apple.Xcode"))
        XCTAssertEqual(PresetSerialization.rule(fromLine: "url:github.com/*"), .url(pattern: "github.com/*"))
        XCTAssertEqual(PresetSerialization.rule(fromLine: "  url: x.com/home "), .url(pattern: "x.com/home"))
        XCTAssertNil(PresetSerialization.rule(fromLine: "garbage"))
        XCTAssertNil(PresetSerialization.rule(fromLine: "app:"))
    }

    func testPresetRecordRoundTrip() {
        let original = BuiltinPresets.writeCode
        let record = PresetSerialization.record(from: original, createdAt: t0, updatedAt: t0)
        let restored = PresetSerialization.preset(from: record)
        XCTAssertEqual(restored, original)
    }

    func testMalformedJSONYieldsEmptyRules() {
        let rules = PresetSerialization.rules(fromJSON: "not json")
        XCTAssertTrue(rules.green.isEmpty)
        XCTAssertTrue(rules.red.isEmpty)
    }
}
