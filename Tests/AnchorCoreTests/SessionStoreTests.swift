import XCTest
@testable import AnchorCore

final class SessionStoreTests: XCTestCase {

    private func makeStore() throws -> SessionStore {
        try SessionStore(.memory)
    }

    // whole-second epochs so Int64 storage round-trips exactly
    private let t1 = Date(timeIntervalSince1970: 1_700_000_000)
    private let t2 = Date(timeIntervalSince1970: 1_700_000_600)
    private let t3 = Date(timeIntervalSince1970: 1_700_001_200)

    func testMigrationLetsUsInsertAndRead() throws {
        let store = try makeStore()
        let s = SessionRecord(id: "s1", presetId: "builtin.write-code", startedAt: t1)
        try store.upsertSession(s)
        XCTAssertEqual(try store.session(id: "s1"), s)
    }

    func testSessionRoundTripsAllFields() throws {
        let store = try makeStore()
        let s = SessionRecord(
            id: "s1", presetId: "p", startedAt: t1, endedAt: t2,
            greenSeconds: 3600, graySeconds: 600, redSeconds: 120,
            driftCount: 7, longestStreakSeconds: 1800, deepScore: 73
        )
        try store.upsertSession(s)
        XCTAssertEqual(try store.session(id: "s1"), s)
    }

    func testUpsertReplacesExistingSession() throws {
        let store = try makeStore()
        var s = SessionRecord(id: "s1", presetId: "p", startedAt: t1)
        try store.upsertSession(s)
        s.deepScore = 88
        s.endedAt = t2
        try store.upsertSession(s)
        XCTAssertEqual(try store.session(id: "s1")?.deepScore, 88)
        XCTAssertEqual(try store.session(id: "s1")?.endedAt, t2)
    }

    func testInProgressSessionIsTheOpenOne() throws {
        let store = try makeStore()
        try store.upsertSession(SessionRecord(id: "done", presetId: "p", startedAt: t1, endedAt: t2))
        try store.upsertSession(SessionRecord(id: "open", presetId: "p", startedAt: t3, endedAt: nil))
        XCTAssertEqual(try store.inProgressSession()?.id, "open")
    }

    func testSessionsFilteredByDateRange() throws {
        let store = try makeStore()
        try store.upsertSession(SessionRecord(id: "a", presetId: "p", startedAt: t1))
        try store.upsertSession(SessionRecord(id: "b", presetId: "p", startedAt: t2))
        try store.upsertSession(SessionRecord(id: "c", presetId: "p", startedAt: t3))
        let mid = try store.sessions(from: t1.addingTimeInterval(1), to: t3)
        XCTAssertEqual(mid.map(\.id), ["b"])
    }

    func testDriftsRoundTripAndQueryBySession() throws {
        let store = try makeStore()
        try store.upsertSession(SessionRecord(id: "s1", presetId: "p", startedAt: t1))
        let d = DriftRecord(
            id: "d1", sessionId: "s1", occurredAt: t1,
            fromApp: "com.apple.Terminal", fromURL: nil,
            toApp: "com.google.Chrome", toURL: "https://x.com/home",
            durationSeconds: 42, endReason: .tap, nextDestination: "youtube.com"
        )
        try store.insertDrift(d)
        XCTAssertEqual(try store.drifts(sessionId: "s1"), [d])
    }

    func testDriftEndReasonEnumRoundTrips() throws {
        let store = try makeStore()
        try store.upsertSession(SessionRecord(id: "s1", presetId: "p", startedAt: t1))
        for (i, reason) in DriftRecord.EndReason.allCases.enumerated() {
            try store.insertDrift(DriftRecord(id: "d\(i)", sessionId: "s1", occurredAt: t1, toApp: "x", endReason: reason))
        }
        let reasons = try store.drifts(sessionId: "s1").compactMap(\.endReason)
        XCTAssertEqual(Set(reasons), Set(DriftRecord.EndReason.allCases))
    }

    func testDriftsFilteredByTimeRange() throws {
        let store = try makeStore()
        try store.upsertSession(SessionRecord(id: "s1", presetId: "p", startedAt: t1))
        try store.insertDrift(DriftRecord(id: "d1", sessionId: "s1", occurredAt: t1, toApp: "x"))
        try store.insertDrift(DriftRecord(id: "d2", sessionId: "s1", occurredAt: t3, toApp: "y"))
        let early = try store.drifts(from: t1, to: t2)
        XCTAssertEqual(early.map(\.id), ["d1"])
    }

    func testPresetCRUD() throws {
        let store = try makeStore()
        let p = PresetRecord(id: "p1", name: "写代码", rulesJSON: "{}", createdAt: t1, updatedAt: t1)
        try store.upsertPreset(p)
        XCTAssertEqual(try store.presets(), [p])
        try store.deletePreset(id: "p1")
        XCTAssertTrue(try store.presets().isEmpty)
    }

    func testDailyRecapRoundTrips() throws {
        let store = try makeStore()
        let r = DailyRecapRecord(
            date: "2026-06-08", deepScore: 73, narrative: "今天你有 138 分钟的专注。",
            topThievesJSON: "[{\"app\":\"x\"}]", generatedAt: t2
        )
        try store.upsertDailyRecap(r)
        XCTAssertEqual(try store.dailyRecap(date: "2026-06-08"), r)
        XCTAssertNil(try store.dailyRecap(date: "1999-01-01"))
    }

    func testReopeningSamePathPersistsData() throws {
        let path = NSTemporaryDirectory() + "anchor-test-\(ProcessInfo.processInfo.globallyUniqueString).sqlite"
        defer { try? FileManager.default.removeItem(atPath: path) }
        do {
            let store = try SessionStore(.file(path))
            try store.upsertSession(SessionRecord(id: "s1", presetId: "p", startedAt: t1))
        }
        let reopened = try SessionStore(.file(path))
        XCTAssertEqual(try reopened.session(id: "s1")?.id, "s1")
    }
}
