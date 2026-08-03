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
            // 库里是完整的注意力轨迹，默认 0644 意味着同机其它用户能直接读走。
            Self.restrictPermissions(at: path)
        case .memory:
            db = try Connection(.inMemory)
        }
        try db.run("PRAGMA foreign_keys = ON")
        // 第二个实例（已装的 app + swift run，或 Sparkle 更新期间的重启重叠）会让写锁竞争，
        // 没有 busy_timeout 时直接 SQLITE_BUSY 抛错 → 整个持久化静默失效。
        try db.run("PRAGMA busy_timeout = 5000")
        try runMigrations()
    }

    /// `~/Library/Application Support/Anchor/anchor.sqlite`，必要时创建目录。
    public static func defaultPath() -> String {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent("Anchor", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        return dir.appendingPathComponent("anchor.sqlite").path
    }

    /// 把库文件（含 WAL / SHM 旁文件）收成仅本人可读写；目录收成 0700。
    /// 每次启动都执行——老安装升级上来也会被就地修正。
    private static func restrictPermissions(at path: String) {
        let manager = FileManager.default
        for suffix in ["", "-wal", "-shm"] {
            let target = path + suffix
            guard manager.fileExists(atPath: target) else { continue }
            try? manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target)
        }
        let dir = (path as NSString).deletingLastPathComponent
        try? manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir)
    }

    /// 落库前的 URL 脱敏：**只保留 scheme + host + path，丢掉 query 与 fragment**。
    ///
    /// 分区判定用的是内存里的完整 URL，所以这里的裁剪不影响绿/灰/红判定；
    /// 但写进磁盘的历史记录不该留 `?token=…`、`?q=…`（搜索词）、重置密码链接这类东西——
    /// 「数据不离开这台电脑」不等于「什么都可以往磁盘上记」。
    public static func sanitizeURLForStorage(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return raw }
        // 逐字符找最早出现的分隔符即可，不依赖 URL 解析（脏 URL 也要能裁）。
        let cut = raw.firstIndex { $0 == "?" || $0 == "#" }
        guard let cut else { return raw }
        return String(raw[raw.startIndex..<cut])
    }

    // MARK: - migrations

    /// 迁移必须是**原子**的：DDL + 版本号一起提交。
    ///
    /// 否则「建完表但还没写 user_version」时被杀掉，下次启动会重跑 `CREATE TABLE`
    /// → "table already exists" → init 抛错 → `try? SessionStore()` 变成 nil
    /// → 从此静默不落盘（规则存不住、复盘永远"今天还没有数据"），
    /// 只能手动删库才能恢复。
    ///
    /// 注意 `VACUUM` 不能在事务里跑，所以 v2 的回溯脱敏与 VACUUM 分开执行。
    private func runMigrations() throws {
        if try userVersion() < 1 {
            try db.transaction {
                try db.execute(Self.migration1)
                try setUserVersion(1)
            }
        }
        if try userVersion() < 2 {
            try db.transaction {
                try db.execute(Self.migration2)
                try setUserVersion(2)
            }
            try db.execute("VACUUM") // 让被裁掉的 query string 不再残留在空闲页里
        }
        // 未来：if try userVersion() < 3 { try db.transaction { ... } }
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

    /// v2：
    /// 1. `sessions.started_at` 补索引——复盘按时间区间查 session，之前是全表扫。
    /// 2. **回溯脱敏**：老版本把完整 URL（含 `?query`）写进了库，升级时就地裁掉，
    ///    不让历史遗留数据继续躺在磁盘上（见 `sanitizeURLForStorage`）。
    private static let migration2 = """
    CREATE INDEX IF NOT EXISTS idx_sessions_time ON sessions(started_at);
    UPDATE drifts SET to_url   = substr(to_url,   1, instr(to_url,   '?') - 1) WHERE instr(to_url,   '?') > 0;
    UPDATE drifts SET from_url = substr(from_url, 1, instr(from_url, '?') - 1) WHERE instr(from_url, '?') > 0;
    UPDATE drifts SET to_url   = substr(to_url,   1, instr(to_url,   '#') - 1) WHERE instr(to_url,   '#') > 0;
    UPDATE drifts SET from_url = substr(from_url, 1, instr(from_url, '#') - 1) WHERE instr(from_url, '#') > 0;
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
            d.id, d.sessionId, epoch(d.occurredAt), d.fromApp,
            Self.sanitizeURLForStorage(d.fromURL), d.toApp, Self.sanitizeURLForStorage(d.toURL),
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

    // MARK: - 数据留存 / 导出 / 清除（用户对自己数据的控制权）

    /// 默认留存天数。专注复盘的价值窗口是「最近几个月」，不是「永久」——
    /// 无上限增长既是隐私负担也是性能负担。
    public static let defaultRetentionDays = 90

    /// 删除早于 `days` 天的漂移与 session（已结束的）。返回删除的行数。
    /// `days <= 0` 视为"不限制"，直接返回 0。
    @discardableResult
    public func prune(olderThanDays days: Int, now: Date = Date()) throws -> Int {
        guard days > 0 else { return 0 }
        let cutoff = epoch(now.addingTimeInterval(-Double(days) * 86_400))
        // 顺序很重要：`PRAGMA foreign_keys = ON` 下先删父行会违反外键。
        // 而且崩溃恢复写回的 ended_at 可能**早于**该 session 自己的漂移记录
        // （见 recoverCrashedSessionIfAny），所以不能只按时间删 drifts——
        // 必须把即将删掉的 session 的子行一并清掉。
        try db.run(
            """
            DELETE FROM drifts
            WHERE occurred_at < ?
               OR session_id IN (
                    SELECT id FROM sessions WHERE ended_at IS NOT NULL AND ended_at < ?
               )
            """,
            cutoff, cutoff
        )
        let driftsDeleted = db.changes
        try db.run("DELETE FROM sessions WHERE ended_at IS NOT NULL AND ended_at < ?", cutoff)
        let sessionsDeleted = db.changes
        try db.run("DELETE FROM daily_recaps WHERE generated_at < ?", cutoff)
        let recapsDeleted = db.changes
        return driftsDeleted + sessionsDeleted + recapsDeleted
    }

    /// 把全部数据导成 JSON（用户可带走 / 自行检查记录了什么）。
    /// preset 规则也含在内，方便换机迁移。
    public func exportJSON(now: Date = Date()) throws -> Data {
        let allSessions = try db.prepare("SELECT \(Self.sessionCols) FROM sessions ORDER BY started_at")
            .map(Self.mapSession)
        let allDrifts = try db.prepare("SELECT \(Self.driftCols) FROM drifts ORDER BY occurred_at")
            .map(Self.mapDrift)
        let allPresets = try presets()
        let formatter = ISO8601DateFormatter()

        let payload: [String: Any] = [
            "exported_at": formatter.string(from: now),
            "schema_version": try userVersion(),
            "note": "Anchor local export. URLs are stored without query strings or fragments.",
            "sessions": allSessions.map { s -> [String: Any] in
                [
                    "id": s.id, "preset_id": s.presetId,
                    "started_at": formatter.string(from: s.startedAt),
                    "ended_at": s.endedAt.map(formatter.string(from:)) ?? NSNull(),
                    "green_seconds": s.greenSeconds, "gray_seconds": s.graySeconds,
                    "red_seconds": s.redSeconds, "drift_count": s.driftCount,
                    "longest_streak_seconds": s.longestStreakSeconds, "deep_score": s.deepScore,
                ]
            },
            "drifts": allDrifts.map { d -> [String: Any] in
                [
                    "id": d.id, "session_id": d.sessionId,
                    "occurred_at": formatter.string(from: d.occurredAt),
                    "from_app": d.fromApp ?? NSNull(), "from_url": d.fromURL ?? NSNull(),
                    "to_app": d.toApp, "to_url": d.toURL ?? NSNull(),
                    "duration_seconds": d.durationSeconds ?? NSNull(),
                    "end_reason": d.endReason?.rawValue ?? NSNull(),
                ]
            },
            "presets": allPresets.map { p -> [String: Any] in
                ["id": p.id, "name": p.name, "rules_json": p.rulesJSON,
                 "drift_threshold_seconds": p.driftThresholdSeconds]
            },
        ]
        return try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
    }

    /// 清空全部历史（session / drift / 复盘）。**保留 preset 规则**——
    /// 用户要抹掉的是"被记录的行为"，不是自己配好的场景。
    public func wipeHistory() throws {
        try db.run("DELETE FROM drifts")
        try db.run("DELETE FROM sessions")
        try db.run("DELETE FROM daily_recaps")
        try db.run("VACUUM")
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
