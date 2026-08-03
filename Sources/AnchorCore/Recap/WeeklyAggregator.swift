import Foundation

/// 把一周的漂移记录聚合成 `SuggestionEngine` 需要的 `WeeklyInput`。
public enum WeeklyAggregator {

    /// 一天里某 2h 时段漂移 ≥ 这个数即记为"高漂移时段"。
    public static let highDriftPerWindowThreshold = 3

    /// 一个时段的长度（小时）。
    public static let windowHours = 2

    /// 时段的**聚合 key**：格式钉死、与 locale 完全无关，只用于统计 / 比较 / 持久化。
    ///
    /// 这个串**不能直接显示给用户**。它同时是 `windowConsecutiveDays` 的字典 key 和
    /// `Suggestion.target`：一旦让它跟着语言变，同一个时段在中文和英文下就成了两个 key，
    /// 聚合会按语言裂成两组、`target` 也无法跨语言比对。
    /// 要给人看走 `windowDisplayLabel(forKey:)`。
    public static func windowKey(startHour: Int) -> String {
        String(format: "%02d:00–%02d:00", startHour, startHour + windowHours)
    }

    /// 把聚合 key 翻成**显示文案**（跟随系统语言；`NarrativeGenerator` 会把它插进句首）。
    ///
    /// 解析不出小时就原样返回 key——宁可显示得难看，也不要显示成空白。
    public static func windowDisplayLabel(forKey key: String) -> String {
        let hours = key
            .split(separator: "–")
            .compactMap { Int($0.prefix { $0.isNumber }) }
        guard hours.count == 2 else { return key }
        return L("recap.hour_range", hours[0], hours[1])
    }

    /// - Parameter isGreenSource: 起点 app 是否在当前 preset 的绿区（规则 B 需要）。
    public static func weeklyInput(
        presetName: String,
        drifts: [DriftRecord],
        isGreenSource: (String) -> Bool,
        calendar: Calendar = .current
    ) -> WeeklyInput {
        WeeklyInput(
            presetName: presetName,
            driftTop5Days: top5Days(drifts: drifts, calendar: calendar),
            greenAppWeeklyDriftCount: greenSourceCounts(drifts: drifts, isGreenSource: isGreenSource),
            highDriftWindowConsecutiveDays: windowConsecutiveDays(drifts: drifts, calendar: calendar)
        )
    }

    /// 规则 A 输入：每个目的地"进入当日漂移 Top 5"的天数。
    static func top5Days(drifts: [DriftRecord], calendar: Calendar) -> [String: Int] {
        let byDay = Dictionary(grouping: drifts) { calendar.startOfDay(for: $0.occurredAt) }
        var days: [String: Int] = [:]
        for (_, dayDrifts) in byDay {
            var counts: [String: Int] = [:]
            for drift in dayDrifts {
                counts[TopThieves.destinationLabel(for: drift), default: 0] += 1
            }
            let top5 = counts
                .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
                .prefix(5)
            for entry in top5 {
                days[entry.key, default: 0] += 1
            }
        }
        return days
    }

    /// 规则 B 输入：绿区 app 作为漂移起点的本周总次数。
    static func greenSourceCounts(drifts: [DriftRecord], isGreenSource: (String) -> Bool) -> [String: Int] {
        var counts: [String: Int] = [:]
        for drift in drifts {
            if let from = drift.fromApp, isGreenSource(from) {
                counts[from, default: 0] += 1
            }
        }
        return counts
    }

    /// 规则 C 输入：每个 2h 时段的"连续高漂移天数"（取最长连续段）。
    static func windowConsecutiveDays(drifts: [DriftRecord], calendar: Calendar) -> [String: Int] {
        // (windowKey, dayIndex) → 漂移次数。key 走 `windowKey`，不是展示文案。
        var perWindowDay: [String: [Int: Int]] = [:]
        for drift in drifts {
            let comps = calendar.dateComponents([.hour], from: drift.occurredAt)
            guard let hour = comps.hour else { continue }
            let windowStart = (hour / windowHours) * windowHours
            let label = windowKey(startHour: windowStart)
            let dayIndex = Int(calendar.startOfDay(for: drift.occurredAt).timeIntervalSince1970 / 86_400)
            perWindowDay[label, default: [:]][dayIndex, default: 0] += 1
        }

        var result: [String: Int] = [:]
        for (label, dayCounts) in perWindowDay {
            let highDays = dayCounts.filter { $0.value >= highDriftPerWindowThreshold }.keys.sorted()
            guard !highDays.isEmpty else { continue }
            var best = 1, run = 1
            for (previous, current) in zip(highDays, highDays.dropFirst()) {
                run = (current == previous + 1) ? run + 1 : 1
                best = max(best, run)
            }
            result[label] = best
        }
        return result
    }
}
