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
        public let presetName: String
        public let driftCount: Int
        public let topDestination: String?    // 如 "GitHub trending"
        public let topDestinationCount: Int
        public let consecutiveDaysWithSameTopDest: Int
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

    private func paragraph1(_ input: Input) -> String {
        let hours = Int(input.deepMinutes / 60)
        let mins = Int(input.deepMinutes.truncatingRemainder(dividingBy: 60))
        let durationLabel = hours > 0 ? "\(hours) 小时 \(mins) 分钟" : "\(mins) 分钟"

        let longest = Int(input.longestStreakMinutes)
        let streakRange: String
        if let start = input.streakStartLabel, let end = input.streakEndLabel {
            streakRange = "（\(start)–\(end)）"
        } else {
            streakRange = ""
        }

        return "今天你有 \(durationLabel) 的真正专注，最长一段 \(longest) 分钟\(streakRange)（场景：\(input.presetName)）。"
    }

    private func paragraph2(_ input: Input) -> String {
        guard input.driftCount > 0 else { return "" }

        if let top = input.topDestination,
           input.topDestinationCount > 0,
           Double(input.topDestinationCount) / Double(input.driftCount) >= 0.3 {
            var line = "漂出去 \(input.driftCount) 次，其中 \(input.topDestinationCount) 次都去了 \(top)"
            if input.consecutiveDaysWithSameTopDest >= 2 {
                line += " —— 连续第 \(input.consecutiveDaysWithSameTopDest) 天了。要加进黑名单吗？"
            } else {
                line += "。"
            }
            return line
        } else {
            return "漂出去 \(input.driftCount) 次，没有特别突出的去处——今天属于「无意识切换」型，不是被某个特定 app 吸住。"
        }
    }

    private func paragraph3(_ input: Input) -> String {
        guard let window = input.hardestTimeWindow,
              input.hardestWindowDaysOutOf7 >= 3 else {
            return ""
        }
        return "\(window) 是你今天最难稳住的时段，过去 7 天有 \(input.hardestWindowDaysOutOf7) 天也是。可能不是意志力，是节律。"
    }
}
