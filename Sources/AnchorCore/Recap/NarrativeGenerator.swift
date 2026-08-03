import Foundation

/// 把当日数据翻译成"朋友写给你的复盘信"。
///
/// v1 用模板引擎，避免 LLM 幻觉 + 保持 local-first。
/// v2 切换 Apple Foundation Models（fallback 留模板）。
public struct NarrativeGenerator {

    public struct Input {
        public let deepMinutes: Double
        public let longestStreakMinutes: Double
        public let streakStartLabel: String?  // 如 "11:03"
        public let streakEndLabel: String?    // 如 "11:50"
        /// 场景名。传**显示名**（`Preset.displayName`），不是持久化的 `name`。
        public let presetName: String
        public let driftCount: Int
        public let topDestination: String?    // 如 "GitHub trending"
        public let topDestinationCount: Int
        public let consecutiveDaysWithSameTopDest: Int
        /// 如 "14:00–16:00"。传 `WeeklyAggregator.windowDisplayLabel(forKey:)` 的**显示文案**，
        /// 不是聚合用的 window key——它会被原样插进句首。
        public let hardestTimeWindow: String? // 如 "14:00–16:00"
        public let hardestWindowDaysOutOf7: Int

        public init(
            deepMinutes: Double,
            longestStreakMinutes: Double,
            streakStartLabel: String? = nil,
            streakEndLabel: String? = nil,
            presetName: String,
            driftCount: Int,
            topDestination: String? = nil,
            topDestinationCount: Int = 0,
            consecutiveDaysWithSameTopDest: Int = 0,
            hardestTimeWindow: String? = nil,
            hardestWindowDaysOutOf7: Int = 0
        ) {
            self.deepMinutes = deepMinutes
            self.longestStreakMinutes = longestStreakMinutes
            self.streakStartLabel = streakStartLabel
            self.streakEndLabel = streakEndLabel
            self.presetName = presetName
            self.driftCount = driftCount
            self.topDestination = topDestination
            self.topDestinationCount = topDestinationCount
            self.consecutiveDaysWithSameTopDest = consecutiveDaysWithSameTopDest
            self.hardestTimeWindow = hardestTimeWindow
            self.hardestWindowDaysOutOf7 = hardestWindowDaysOutOf7
        }
    }

    public init() {}

    public func generate(input: Input) -> String {
        let lines = [
            paragraph1(input),
            paragraph2(input),
            paragraph3(input)
        ].filter { !$0.isEmpty }

        return lines.joined(separator: "\n\n")
    }

    // MARK: - private

    /// 每个分支都是**一句完整的话**，在格式化之前就选定。
    ///
    /// 原来是"词干 + 括号 + 后缀"拼出来的：`line += "。"` / `line += " —— 连续第 n 天了。…"`。
    /// 句尾标点、括号形状、破折号、语序在别的语言里全都不一样，把句号当成一个可拼接的
    /// 字符串来加，只对中文成立。所以这里改成：先判断走哪句，再一次性 `L(key, args…)`。
    private func paragraph1(_ input: Input) -> String {
        let durationLabel = DurationLabel.text(minutes: input.deepMinutes)
        let longestLabel = DurationLabel.text(minutes: input.longestStreakMinutes)

        if let start = input.streakStartLabel, let end = input.streakEndLabel {
            return L(
                "narrative.p1.with_streak_range",
                durationLabel, longestLabel, start, end, input.presetName
            )
        }
        return L("narrative.p1.plain", durationLabel, longestLabel, input.presetName)
    }

    private func paragraph2(_ input: Input) -> String {
        guard input.driftCount > 0 else { return "" }

        if let top = input.topDestination,
           input.topDestinationCount > 0,
           Double(input.topDestinationCount) / Double(input.driftCount) >= 0.3 {
            // "连续第 N 天" 是**另一句话**，不是同一句话的后缀。
            if input.consecutiveDaysWithSameTopDest >= 2 {
                return L(
                    "narrative.p2.top_destination_streak",
                    input.driftCount, input.topDestinationCount, top,
                    input.consecutiveDaysWithSameTopDest
                )
            }
            return L("narrative.p2.top_destination", input.driftCount, input.topDestinationCount, top)
        } else {
            return L("narrative.p2.scattered", input.driftCount)
        }
    }

    private func paragraph3(_ input: Input) -> String {
        guard let window = input.hardestTimeWindow,
              input.hardestWindowDaysOutOf7 >= 3 else {
            return ""
        }
        return L("narrative.p3.hardest_window", window, input.hardestWindowDaysOutOf7)
    }
}

/// 时长文案的唯一出口（秒 / 分 / 时）。复盘窗口与叙事共用同一套词汇，
/// 免得同一个「12 分钟」在两处被翻成两种说法。
///
/// 两件事故意做在这里：
/// - **单位是文案的一部分**（`"%1$lld 分钟"` / `"%1$lld min"`），不是 `"\(n) " + 单位`；
/// - **超过一小时要进位**：125 分钟读成 "125 分钟" 是 bug。
///
/// 所有说法都写成与数量无关（"12 min" 而不是 "12 minutes"），
/// 这样英 / 德 / 俄不需要 `.stringsdict` 复数规则。
public enum DurationLabel {

    /// 秒 → 文案。不足 1 分钟显示秒（"0 分钟" 读起来像 bug）。
    public static func text(seconds: Int) -> String {
        let total = max(0, seconds)
        guard total >= 60 else { return L("recap.duration.seconds", total) }
        return text(totalMinutes: total / 60)
    }

    /// 分钟（可带小数，向下取整）→ 文案。
    public static func text(minutes: Double) -> String {
        text(totalMinutes: Int(max(0, minutes)))
    }

    static func text(totalMinutes: Int) -> String {
        let (hours, minutes) = split(totalMinutes: totalMinutes)
        if hours == 0 { return L("recap.duration.minutes", minutes) }
        if minutes == 0 { return L("recap.duration.hours", hours) }
        return L("recap.duration.hours_minutes", hours, minutes)
    }

    /// 进位后的 (小时, 分钟)。
    ///
    /// 单独暴露一层是为了**能测进位**：文案在单元测试里只会拿到 key，
    /// 参数会被 `String(format:)` 丢掉，"138 分钟要读成 2 小时 18 分钟"只能在这里验。
    static func split(totalMinutes: Int) -> (hours: Int, minutes: Int) {
        let total = max(0, totalMinutes)
        return (total / 60, total % 60)
    }
}
