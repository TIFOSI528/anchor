import XCTest
@testable import AnchorCore

private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

final class SessionAccumulatorTests: XCTestCase {

    func testAccumulatesZoneSecondsByTimestamps() {
        var acc = SessionAccumulator()
        acc.transition(to: .green, at: at(0))
        acc.transition(to: .gray, at: at(600))   // 10min green
        acc.transition(to: .red, at: at(660))    // 1min gray
        acc.transition(to: .green, at: at(720))  // 1min red
        let totals = acc.snapshot(at: at(1320))  // 10min more green

        XCTAssertEqual(totals.greenSeconds, 1200)
        XCTAssertEqual(totals.graySeconds, 60)
        XCTAssertEqual(totals.redSeconds, 60)
        XCTAssertEqual(totals.onlineSeconds, 1320)
    }

    func testDriftCountOnlyOnLeavingGreen() {
        var acc = SessionAccumulator()
        acc.transition(to: .green, at: at(0))
        acc.transition(to: .gray, at: at(10))   // drift 1
        acc.transition(to: .red, at: at(20))    // same excursion, not a new drift
        acc.transition(to: .green, at: at(30))
        acc.transition(to: .red, at: at(40))    // drift 2
        XCTAssertEqual(acc.snapshot(at: at(50)).driftCount, 2)
    }

    func testLongestStreakTracksLongestGreenInterval() {
        var acc = SessionAccumulator()
        acc.transition(to: .green, at: at(0))
        acc.transition(to: .gray, at: at(300))
        acc.transition(to: .green, at: at(360))
        acc.transition(to: .gray, at: at(1360)) // 1000s streak
        XCTAssertEqual(acc.snapshot(at: at(1400)).longestStreakSeconds, 1000)
    }

    func testSnapshotIncludesOpenIntervalWithoutMutating() {
        var acc = SessionAccumulator()
        acc.transition(to: .green, at: at(0))
        XCTAssertEqual(acc.snapshot(at: at(100)).greenSeconds, 100)
        XCTAssertEqual(acc.snapshot(at: at(200)).greenSeconds, 200)
    }

    func testNilZoneStopsClock() {
        var acc = SessionAccumulator()
        acc.transition(to: .green, at: at(0))
        acc.transition(to: nil, at: at(60))      // paused
        XCTAssertEqual(acc.snapshot(at: at(1000)).greenSeconds, 60)
    }

    func testSameZoneTransitionIsNoOpKeepingStreakIntact() {
        var acc = SessionAccumulator()
        acc.transition(to: .green, at: at(0))
        acc.transition(to: .green, at: at(500))  // no-op
        acc.transition(to: .gray, at: at(1000))
        XCTAssertEqual(acc.snapshot(at: at(1000)).longestStreakSeconds, 1000)
    }
}

final class DriftLoggerTests: XCTestCase {

    private func makeLogger() -> DriftLogger {
        var n = 0
        return DriftLogger(sessionId: "s1", makeId: { n += 1; return "d\(n)" })
    }

    func testOpenThenReturnProducesOneRecord() {
        let logger = makeLogger()
        let green = AppContext(bundleId: "com.apple.Xcode")
        let gray = AppContext(bundleId: "com.apple.iCal")

        XCTAssertNil(logger.enterNonGreen(from: green, to: gray, at: at(0)))
        let closed = logger.returnToGreen(at: at(45), reason: .tap)

        XCTAssertEqual(closed?.id, "d1")
        XCTAssertEqual(closed?.fromApp, "com.apple.Xcode")
        XCTAssertEqual(closed?.toApp, "com.apple.iCal")
        XCTAssertEqual(closed?.durationSeconds, 45)
        XCTAssertEqual(closed?.endReason, .tap)
        XCTAssertNil(logger.pending)
    }

    func testHopClosesPreviousWithNextDestination() {
        let logger = makeLogger()
        let green = AppContext(bundleId: "green.app")
        let first = AppContext(bundleId: "com.google.Chrome", url: URL(string: "https://x.com/home"))
        let second = AppContext(bundleId: "com.bilibili.app")

        logger.enterNonGreen(from: green, to: first, at: at(0))
        let closed = logger.enterNonGreen(from: nil, to: second, at: at(30))

        XCTAssertEqual(closed?.nextDestination, "com.bilibili.app")
        XCTAssertEqual(closed?.durationSeconds, 30)
        XCTAssertNil(closed?.endReason)
        // second leg starts from the first destination
        XCTAssertEqual(logger.pending?.from, first)
    }

    func testSessionEndedClosesWithSessionEndReason() {
        let logger = makeLogger()
        logger.enterNonGreen(from: nil, to: AppContext(bundleId: "x"), at: at(0))
        XCTAssertEqual(logger.sessionEnded(at: at(10))?.endReason, .sessionEnd)
    }

    func testSameDestinationReentryIsNoOp() {
        let logger = makeLogger()
        let ctx = AppContext(bundleId: "x")
        logger.enterNonGreen(from: nil, to: ctx, at: at(0))
        XCTAssertNil(logger.enterNonGreen(from: nil, to: ctx, at: at(5)))
        XCTAssertEqual(logger.pending?.openedAt, at(0)) // 原始开始时间不被重置
    }
}

final class SlackingPolicyTests: XCTestCase {

    func testFirstThreeAreSoftFourthIsHard() {
        let policy = SlackingPolicy()
        XCTAssertEqual(policy.mode(usedToday: 0), .soft)
        XCTAssertEqual(policy.mode(usedToday: 2), .soft)
        XCTAssertEqual(policy.mode(usedToday: 3), .hard)
        XCTAssertEqual(policy.mode(usedToday: 10), .hard)
    }

    func testCounterRollsOverAtMidnight() {
        var day = "2026-06-10"
        let counter = SlackingCounter(dayKey: { day })
        counter.increment()
        counter.increment()
        XCTAssertEqual(counter.usedToday, 2)
        day = "2026-06-11"
        XCTAssertEqual(counter.usedToday, 0)
        XCTAssertEqual(counter.increment(), 1)
    }
}

final class RecapSchedulerTests: XCTestCase {

    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int = 0) -> Date {
        utc.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    func testNextDailyLaterToday() {
        let next = RecapScheduler.nextDaily(hour: 22, after: date(2026, 6, 10, 9), calendar: utc)
        XCTAssertEqual(next, date(2026, 6, 10, 22))
    }

    func testNextDailyRollsToTomorrowWhenPast() {
        let next = RecapScheduler.nextDaily(hour: 22, after: date(2026, 6, 10, 23), calendar: utc)
        XCTAssertEqual(next, date(2026, 6, 11, 22))
    }

    func testNextWeeklySunday2100() {
        // 2026-06-10 is a Wednesday; next Sunday is 06-14.
        let next = RecapScheduler.nextWeekly(weekday: 1, hour: 21, after: date(2026, 6, 10, 9), calendar: utc)
        XCTAssertEqual(next, date(2026, 6, 14, 21))
    }
}
