import Foundation
import SQLite

/// 本地 SQLite 持久化层（DataAccessor）。
///
/// - 路径：`~/Library/Application Support/Anchor/anchor.sqlite`（见 technical-architecture §三）
/// - WAL 模式，避免读写锁竞争
/// - `user_version` 驱动的迁移框架，未来加表只需追加一个 migration
///
/// 不变量（technical-architecture §八）：**SQLite 写永远不应阻塞主线程**。
/// 本类的方法是同步的；App 层通过单一串行队列异步调用（见 PR #23）。
///
/// `@unchecked Sendable`：Connection 本身不做线程安全承诺，约定是所有访问都
/// 经由调用方的同一条串行队列（AppCoordinator.writeQueue）。
public final class SessionStore: @unchecked Sendable {

    public enum Storage {
        case file(String)
        case memory
    }

    private let db: Connection

    public init(_ storage: Storage = .file(SessionStore.defaultPath())) throws {
        switch storage {
        case let .file(path):
            db = try Connection(path)
            try db.run("PRAGMA journal_mode = WAL")
        case .memory:
            db = try Connection(.inMemory)
        }
        try db.run("PRAGMA foreign_keys = ON")
        try runMigrations()
    }

    /// `~/Library/Application Support/Anchor/anchor.sqlite`，必要时创建目录。
    public static func defaultPath() -> String {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent("Anchor", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("anchor.sqlite").path
    }

    // MARK: - migrations

    private func runMigrations() throws {
        if try userVersion() < 1 {
            try db.execute(Self.migration1)
            try setUserVersion(1)
        }
        // 未来：if try userVersion() < 2 { ... ; try setUserVersion(2) }
    }

    private func userVersion() throws -> Int {
        Int(try db.scalar("PRAGMA user_version") as? Int64 ?? 0)
    }

    private func setUserVersion(_ version: Int) throws {
        // PRAGMA 不支持 `?` 绑定；version 由代码控制，非用户输入，拼接安全。
        try db.run("PRAGMA user_version = \(version)")
    }

    private static let migration1 = """
    CREATE TABLE sessions (
        id TEXT PRIMARY KEY,
        preset_id TEXT,
        started_at INTEGER,
        ended_at INTEGER,
        green_seconds INTEGER,
        gray_seconds INTEGER,
        red_seconds INTEGER,
        drift_count INTEGER,
        longest_streak_seconds INTEGER,
        deep_score INTEGER
    );
    CREATE TABLE drifts (
        id TEXT PRIMARY KEY,
        session_id TEXT REFERENCES sessions(id),
        occurred_at INTEGER,
        from_app TEXT,
        from_url TEXT,
        to_app TEXT,
        to_url TEXT,
        duration_seconds INTEGER,
        end_reason TEXT,
        next_destination TEXT
    );
    CREATE TABLE presets (
        id TEXT PRIMARY KEY,
        name TEXT,
        rules_json TEXT,
        drift_threshold_seconds INTEGER DEFAULT 60,
        created_at INTEGER,
        updated_at INTEGER
    );
    CREATE TABLE daily_recaps (
        date TEXT PRIMARY KEY,
        deep_score INTEGER,
        narrative TEXT,
        top_thieves_json TEXT,
        generated_at INTEGER
    );
    CREATE INDEX idx_drifts_session ON drifts(session_id);
    CREATE INDEX idx_drifts_time ON drifts(occurred_at);
    """

    // MARK: - sessions

    public func upsertSession(_ s: SessionRecord) throws {
        try db.run(
            """
            INSERT OR REPLACE INTO sessions
            (id, preset_id, started_at, ended_at, green_seconds, gray_seconds,
             red_seconds, drift_count, longest_streak_seconds, deep_score)
            VALUES (?,?,?,?,?,?,?,?,?,?)
            """,
            s.id, s.presetId, epoch(s.startedAt), epochOpt(s.endedAt),
            Int64(s.greenSeconds), Int64(s.graySeconds), Int64(s.redSeconds),
            Int64(s.driftCount), Int64(s.longestStreakSeconds), Int64(s.deepScore)
        )
    }

    public func session(id: String) throws -> SessionRecord? {
        for row in try db.prepare("SELECT \(Self.sessionCols) FROM sessions WHERE id = ?", id) {
            return Self.mapSession(row)
        }
        return nil
    }

    /// 起始时间落在 [from, to) 区间内的 session，按 started_at 升序。
    public func sessions(from: Date, to: Date) throws -> [SessionRecord] {
        try db.prepare(
            "SELECT \(Self.sessionCols) FROM sessions WHERE started_at >= ? AND started_at < ? ORDER BY started_at",
            epoch(from), epoch(to)
        ).map(Self.mapSession)
    }

    /// 还没结束的 session（ended_at IS NULL）——用于 crash 后恢复"进行中 session"。
    public func inProgressSession() throws -> SessionRecord? {
        for row in try db.prepare(
            "SELECT \(Self.sessionCols) FROM sessions WHERE ended_at IS NULL ORDER BY started_at DESC LIMIT 1"
        ) {
            return Self.mapSession(row)
        }
        return nil
    }

    // MARK: - drifts

    public func insertDrift(_ d: DriftRecord) throws {
        try db.run(
            """
            INSERT OR REPLACE INTO drifts
            (id, session_id, occurred_at, from_app, from_url, to_app, to_url,
             duration_seconds, end_reason, next_destination)
            VALUES (?,?,?,?,?,?,?,?,?,?)
            """,
            d.id, d.sessionId, epoch(d.occurredAt), d.fromApp, d.fromURL, d.toApp, d.toURL,
            d.durationSeconds.map(Int64.init), d.endReason?.rawValue, d.nextDestination
        )
    }

    public func drifts(sessionId: String) throws -> [DriftRecord] {
        try db.prepare(
            "SELECT \(Self.driftCols) FROM drifts WHERE session_id = ? ORDER BY occurred_at",
            sessionId
        ).map(Self.mapDrift)
    }

    public func drifts(from: Date, to: Date) throws -> [DriftRecord] {
        try db.prepare(
            "SELECT \(Self.driftCols) FROM drifts WHERE occurred_at >= ? AND occurred_at < ? ORDER BY occurred_at",
            epoch(from), epoch(to)
        ).map(Self.mapDrift)
    }

    // MARK: - presets

    public func upsertPreset(_ p: PresetRecord) throws {
        try db.run(
            """
            INSERT OR REPLACE INTO presets
            (id, name, rules_json, drift_threshold_seconds, created_at, updated_at)
            VALUES (?,?,?,?,?,?)
            """,
            p.id, p.name, p.rulesJSON, Int64(p.driftThresholdSeconds), epoch(p.createdAt), epoch(p.updatedAt)
        )
    }

    public func presets() throws -> [PresetRecord] {
        try db.prepare("SELECT \(Self.presetCols) FROM presets ORDER BY created_at").map(Self.mapPreset)
    }

    public func deletePreset(id: String) throws {
        try db.run("DELETE FROM presets WHERE id = ?", id)
    }

    // MARK: - daily recaps

    public func upsertDailyRecap(_ r: DailyRecapRecord) throws {
        try db.run(
            """
            INSERT OR REPLACE INTO daily_recaps
            (date, deep_score, narrative, top_thieves_json, generated_at)
            VALUES (?,?,?,?,?)
            """,
            r.date, Int64(r.deepScore), r.narrative, r.topThievesJSON, epoch(r.generatedAt)
        )
    }

    public func dailyRecap(date: String) throws -> DailyRecapRecord? {
        for row in try db.prepare("SELECT \(Self.recapCols) FROM daily_recaps WHERE date = ?", date) {
            return Self.mapRecap(row)
        }
        return nil
    }

    // MARK: - row mapping

    private static let sessionCols =
        "id, preset_id, started_at, ended_at, green_seconds, gray_seconds, red_seconds, drift_count, longest_streak_seconds, deep_score"
    private static let driftCols =
        "id, session_id, occurred_at, from_app, from_url, to_app, to_url, duration_seconds, end_reason, next_destination"
    private static let presetCols =
        "id, name, rules_json, drift_threshold_seconds, created_at, updated_at"
    private static let recapCols =
        "date, deep_score, narrative, top_thieves_json, generated_at"

    private static func mapSession(_ row: [Binding?]) -> SessionRecord {
        SessionRecord(
            id: str(row[0]),
            presetId: str(row[1]),
            startedAt: date(row[2]),
            endedAt: dateOpt(row[3]),
            greenSeconds: int(row[4]),
            graySeconds: int(row[5]),
            redSeconds: int(row[6]),
            driftCount: int(row[7]),
            longestStreakSeconds: int(row[8]),
            deepScore: int(row[9])
        )
    }

    private static func mapDrift(_ row: [Binding?]) -> DriftRecord {
        DriftRecord(
            id: str(row[0]),
            sessionId: str(row[1]),
            occurredAt: date(row[2]),
            fromApp: row[3] as? String,
            fromURL: row[4] as? String,
            toApp: str(row[5]),
            toURL: row[6] as? String,
            durationSeconds: (row[7] as? Int64).map(Int.init),
            endReason: (row[8] as? String).flatMap(DriftRecord.EndReason.init(rawValue:)),
            nextDestination: row[9] as? String
        )
    }

    private static func mapPreset(_ row: [Binding?]) -> PresetRecord {
        PresetRecord(
            id: str(row[0]),
            name: str(row[1]),
            rulesJSON: str(row[2]),
            driftThresholdSeconds: int(row[3]),
            createdAt: date(row[4]),
            updatedAt: date(row[5])
        )
    }

    private static func mapRecap(_ row: [Binding?]) -> DailyRecapRecord {
        DailyRecapRecord(
            date: str(row[0]),
            deepScore: int(row[1]),
            narrative: str(row[2]),
            topThievesJSON: row[3] as? String ?? "[]",
            generatedAt: date(row[4])
        )
    }

    // MARK: - binding helpers

    private func epoch(_ d: Date) -> Int64 { Int64(d.timeIntervalSince1970) }
    private func epochOpt(_ d: Date?) -> Int64? { d.map { Int64($0.timeIntervalSince1970) } }

    private static func str(_ b: Binding?) -> String { b as? String ?? "" }
    private static func int(_ b: Binding?) -> Int { Int(b as? Int64 ?? 0) }
    private static func date(_ b: Binding?) -> Date { Date(timeIntervalSince1970: TimeInterval(b as? Int64 ?? 0)) }
    private static func dateOpt(_ b: Binding?) -> Date? { (b as? Int64).map { Date(timeIntervalSince1970: TimeInterval($0)) } }
}
