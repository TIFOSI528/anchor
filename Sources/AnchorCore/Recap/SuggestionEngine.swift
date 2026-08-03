import Foundation

/// 周回顾的一条可执行建议（daily-recap-spec §六）。必须可解释（带数据来源）。
public struct Suggestion: Equatable, Sendable {
    public enum Kind: String, Sendable, Equatable {
        case blacklist     // 规则 A
        case presetAdjust  // 规则 B
        case rhythm        // 规则 C
    }

    public let kind: Kind
    /// 规则要作用的对象。是**聚合 key**（bundle id / URL host / `WeeklyAggregator.windowKey`），
    /// 与语言无关——上层会拿它去改 preset 规则，所以不能塞展示文案。
    public let target: String
    public let message: String
    public let rationale: String

    public init(kind: Kind, target: String, message: String, rationale: String) {
        self.kind = kind
        self.target = target
        self.message = message
        self.rationale = rationale
    }
}

/// 周回顾的聚合输入（由上层从一周的 session/drift 数据算好后传入）。
public struct WeeklyInput: Sendable {
    /// 场景名。传**显示名**（`Preset.displayName`），它会直接进文案。
    public let presetName: String
    /// 规则 A：某 URL/app 进入漂移 Top 5 的天数。
    public let driftTop5Days: [String: Int]
    /// 规则 B：绿区 app 本周触发漂移的次数。
    public let greenAppWeeklyDriftCount: [String: Int]
    /// 规则 C：某固定时段连续高漂移的天数。key 是 `WeeklyAggregator.windowKey`（不可显示）。
    public let highDriftWindowConsecutiveDays: [String: Int]

    public init(
        presetName: String,
        driftTop5Days: [String: Int] = [:],
        greenAppWeeklyDriftCount: [String: Int] = [:],
        highDriftWindowConsecutiveDays: [String: Int] = [:]
    ) {
        self.presetName = presetName
        self.driftTop5Days = driftTop5Days
        self.greenAppWeeklyDriftCount = greenAppWeeklyDriftCount
        self.highDriftWindowConsecutiveDays = highDriftWindowConsecutiveDays
    }
}

/// 周回顾建议引擎（规则版，不用 LLM）。每周至多一条，优先级 A > B > C。
public enum SuggestionEngine {

    public static let blacklistDaysThreshold = 5        // 漂移 Top 5 超过 5 天
    public static let presetAdjustDriftThreshold = 20   // 绿区 app 每周漂移 > 20 次
    public static let rhythmConsecutiveDaysThreshold = 4 // 固定时段连续 4+ 天

    /// 返回本周唯一一条建议；无任何规则命中时返回 nil。
    public static func weeklySuggestion(_ input: WeeklyInput) -> Suggestion? {
        // 规则 A：黑名单建议（最高优先级）
        if let entry = strongest(input.driftTop5Days, over: blacklistDaysThreshold) {
            return Suggestion(
                kind: .blacklist,
                target: entry.key,
                message: L("suggestion.blacklist.message", entry.key, input.presetName),
                rationale: L("suggestion.blacklist.rationale", entry.value)
            )
        }

        // 规则 B：preset 调整建议
        if let entry = strongest(input.greenAppWeeklyDriftCount, over: presetAdjustDriftThreshold) {
            return Suggestion(
                kind: .presetAdjust,
                target: entry.key,
                message: L("suggestion.preset_adjust.message", entry.key, input.presetName),
                rationale: L("suggestion.preset_adjust.rationale", entry.value)
            )
        }

        // 规则 C：节律建议
        if let entry = atLeast(input.highDriftWindowConsecutiveDays, threshold: rhythmConsecutiveDaysThreshold) {
            return Suggestion(
                kind: .rhythm,
                target: entry.key,
                // target 留聚合 key，文案里用显示文案——两件事分开，别让展示串跑进字典 key。
                message: L("suggestion.rhythm.message", WeeklyAggregator.windowDisplayLabel(forKey: entry.key)),
                rationale: L("suggestion.rhythm.rationale", entry.value)
            )
        }

        return nil
    }

    // MARK: - private

    /// 取值 **严格大于** threshold 的最强项（值最大；并列按 key 升序）。
    private static func strongest(_ map: [String: Int], over threshold: Int) -> (key: String, value: Int)? {
        pick(map.filter { $0.value > threshold })
    }

    /// 取值 **大于等于** threshold 的最强项。
    private static func atLeast(_ map: [String: Int], threshold: Int) -> (key: String, value: Int)? {
        pick(map.filter { $0.value >= threshold })
    }

    private static func pick(_ filtered: [String: Int]) -> (key: String, value: Int)? {
        filtered
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .first
            .map { ($0.key, $0.value) }
    }
}
