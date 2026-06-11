import Foundation

/// 一次专注 session 的持久化记录（对应 `sessions` 表，见 daily-recap-spec §VII）。
public struct SessionRecord: Equatable, Sendable {
    public var id: String
    public var presetId: String
    public var startedAt: Date
    /// nil 表示 session 仍在进行中（用于 crash 恢复）。
    public var endedAt: Date?
    public var greenSeconds: Int
    public var graySeconds: Int
    public var redSeconds: Int
    public var driftCount: Int
    public var longestStreakSeconds: Int
    public var deepScore: Int

    public init(
        id: String,
        presetId: String,
        startedAt: Date,
        endedAt: Date? = nil,
        greenSeconds: Int = 0,
        graySeconds: Int = 0,
        redSeconds: Int = 0,
        driftCount: Int = 0,
        longestStreakSeconds: Int = 0,
        deepScore: Int = 0
    ) {
        self.id = id
        self.presetId = presetId
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.greenSeconds = greenSeconds
        self.graySeconds = graySeconds
        self.redSeconds = redSeconds
        self.driftCount = driftCount
        self.longestStreakSeconds = longestStreakSeconds
        self.deepScore = deepScore
    }
}

/// 一次漂移事件的持久化记录（对应 `drifts` 表）。
public struct DriftRecord: Equatable, Sendable {
    /// 漂移结束方式。原始值即数据库里存的字符串。
    public enum EndReason: String, Sendable, CaseIterable {
        case tap
        case longPress = "long_press"
        case swipe
        case autoReturn = "auto_return"
        case sessionEnd = "session_end"
    }

    public var id: String
    public var sessionId: String
    public var occurredAt: Date
    public var fromApp: String?
    public var fromURL: String?
    public var toApp: String
    public var toURL: String?
    public var durationSeconds: Int?
    public var endReason: EndReason?
    /// 漂移链分析用：这次漂移之后又去了哪。
    public var nextDestination: String?

    public init(
        id: String,
        sessionId: String,
        occurredAt: Date,
        fromApp: String? = nil,
        fromURL: String? = nil,
        toApp: String,
        toURL: String? = nil,
        durationSeconds: Int? = nil,
        endReason: EndReason? = nil,
        nextDestination: String? = nil
    ) {
        self.id = id
        self.sessionId = sessionId
        self.occurredAt = occurredAt
        self.fromApp = fromApp
        self.fromURL = fromURL
        self.toApp = toApp
        self.toURL = toURL
        self.durationSeconds = durationSeconds
        self.endReason = endReason
        self.nextDestination = nextDestination
    }
}

/// 每日复盘的持久化记录（对应 `daily_recaps` 表）。
public struct DailyRecapRecord: Equatable, Sendable {
    /// ISO-8601 日期（yyyy-MM-dd）。
    public var date: String
    public var deepScore: Int
    public var narrative: String
    /// 罪人榜序列化 JSON。
    public var topThievesJSON: String
    public var generatedAt: Date

    public init(
        date: String,
        deepScore: Int,
        narrative: String,
        topThievesJSON: String = "[]",
        generatedAt: Date
    ) {
        self.date = date
        self.deepScore = deepScore
        self.narrative = narrative
        self.topThievesJSON = topThievesJSON
        self.generatedAt = generatedAt
    }
}

/// preset 的持久化记录（对应 `presets` 表）。规则以 JSON 字符串存储。
public struct PresetRecord: Equatable, Sendable {
    public var id: String
    public var name: String
    public var rulesJSON: String
    public var driftThresholdSeconds: Int
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        name: String,
        rulesJSON: String,
        driftThresholdSeconds: Int = 60,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.name = name
        self.rulesJSON = rulesJSON
        self.driftThresholdSeconds = driftThresholdSeconds
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
