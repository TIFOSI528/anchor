import Foundation

/// 一份完整的"今日复盘"数据（Recap 窗口的渲染输入）。
public struct RecapData: Equatable, Sendable {
    public let dateLabel: String
    public let deepScore: Int
    public let narrative: String
    public let segments: [TimelineSegment]
    public let heatmap: DriftHeatmap
    public let thieves: [TimeThief]
    public let chains: [DriftChain]
    public let totals: SessionAccumulator.Totals

    public init(
        dateLabel: String,
        deepScore: Int,
        narrative: String,
        segments: [TimelineSegment],
        heatmap: DriftHeatmap,
        thieves: [TimeThief],
        chains: [DriftChain],
        totals: SessionAccumulator.Totals
    ) {
        self.dateLabel = dateLabel
        self.deepScore = deepScore
        self.narrative = narrative
        self.segments = segments
        self.heatmap = heatmap
        self.thieves = thieves
        self.chains = chains
        self.totals = totals
    }
}

/// 把当日 session/漂移数据组装成 `RecapData`（daily-recap-spec §二 信息架构）。
public enum RecapComposer {

    /// 本周"最难稳住"的时段：按落在该 2 小时窗口里的漂移次数取最多的那个。
    /// 返回的是**聚合 key**（locale 无关），显示前需过 `windowDisplayLabel`。
    static func hardestWindow(in drifts: [DriftRecord], calendar: Calendar) -> String? {
        var counts: [String: Int] = [:]
        for drift in drifts {
            guard let hour = calendar.dateComponents([.hour], from: drift.occurredAt).hour else { continue }
            let bucketStart = hour - (hour % WeeklyAggregator.windowHours)
            counts[WeeklyAggregator.windowKey(startHour: bucketStart), default: 0] += 1
        }
        // 并列时取 key 字典序最小的那个，保证同样输入给出同样输出（否则复盘文案会随机跳）。
        return counts.max { lhs, rhs in
            lhs.value == rhs.value ? lhs.key > rhs.key : lhs.value < rhs.value
        }?.key
    }

    /// 今天的头号目的地已经连续当了多少天头号目的地（含今天）。
    ///
    /// 用于第 2 段那句"连续第 N 天了，要加进黑名单吗？"——只有真的连续才说，
    /// 否则这句话会变成噪音。
    static func consecutiveDaysWithSameTopDestination(
        in drifts: [DriftRecord],
        upTo now: Date,
        calendar: Calendar
    ) -> Int {
        let byDay = Dictionary(grouping: drifts) { calendar.startOfDay(for: $0.occurredAt) }
        func topDestination(on day: Date) -> String? {
            guard let dayDrifts = byDay[day], !dayDrifts.isEmpty else { return nil }
            let counts = Dictionary(grouping: dayDrifts, by: TopThieves.destinationLabel(for:))
                .mapValues(\.count)
            return counts.max { lhs, rhs in
                lhs.value == rhs.value ? lhs.key > rhs.key : lhs.value < rhs.value
            }?.key
        }

        let today = calendar.startOfDay(for: now)
        guard let target = topDestination(on: today) else { return 0 }
        var streak = 0
        var cursor = today
        // 最多回看 7 天：weekDrifts 本身就是 7 天窗口。
        for _ in 0..<7 {
            guard topDestination(on: cursor) == target else { break }
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }

    /// - Parameter displayName: 把原始标签（bundleId / URL host）翻译成给人看的名字。
    ///   统计永远基于原始标签，翻译只发生在展示字段——保证计数不受重名影响。
    public static func compose(
        dateLabel: String,
        presetName: String,
        sessions: [SessionRecord],
        todayDrifts: [DriftRecord],
        weekDrifts: [DriftRecord],
        seriousMode: Bool = false,
        classify: (DriftRecord) -> RecapZone,
        displayName: (String) -> String = { $0 },
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> RecapData {
        // 1. 时间线：每个 session 的区段拼接。
        var intervals: [ZoneInterval] = []
        for session in sessions {
            let end = session.endedAt ?? now
            let drifts = todayDrifts.filter { $0.sessionId == session.id }
            intervals += TimelineBuilder.intervals(
                sessionStart: session.startedAt,
                sessionEnd: end,
                drifts: drifts,
                classify: classify
            )
        }
        let segments = RecapTimeline.segments(from: intervals)
        let rawTotals = RecapTimeline.totals(from: intervals)
        let totals = SessionAccumulator.Totals(
            greenSeconds: rawTotals.greenSeconds,
            graySeconds: rawTotals.graySeconds,
            redSeconds: rawTotals.redSeconds,
            driftCount: todayDrifts.count,
            longestStreakSeconds: rawTotals.longestStreakSeconds
        )

        // 2. Deep Score（公式见 daily-recap-spec §三）。
        let score = DeepScore().compute(input: .init(
            greenMinutes: Double(totals.greenSeconds) / 60,
            grayMinutes: Double(totals.graySeconds) / 60,
            redMinutes: Double(totals.redSeconds) / 60,
            driftCount: totals.driftCount
        ))

        // 3. 罪人榜（score < 30 自动严肃模式，由 TopThieves 处理）。先用原始标签统计。
        let rawThieves = TopThieves.compute(drifts: todayDrifts, deepScore: score, seriousMode: seriousMode)

        // 4. 叙事（topDestination 用解析后的名字进文案，计数用原始标签）。
        //
        // 后三个字段此前**从来没传**，于是叙事第 3 段（节律观察）和第 2 段的
        // "连续第 N 天了，要加进黑名单吗？"这个钩子永远不会出现——spec 承诺三段，
        // 实际只可能渲染出一段。这里用本周漂移把它们算出来。
        let hardestWindowKey = Self.hardestWindow(in: weekDrifts, calendar: calendar)
        let narrative = NarrativeGenerator().generate(input: .init(
            deepMinutes: Double(totals.greenSeconds) / 60,
            longestStreakMinutes: Double(totals.longestStreakSeconds) / 60,
            presetName: presetName,
            driftCount: totals.driftCount,
            topDestination: rawThieves.first.map { displayName($0.label) },
            topDestinationCount: rawThieves.first.map { thief in
                todayDrifts.filter { TopThieves.destinationLabel(for: $0) == thief.label }.count
            } ?? 0,
            consecutiveDaysWithSameTopDest: Self.consecutiveDaysWithSameTopDestination(
                in: weekDrifts, upTo: now, calendar: calendar
            ),
            hardestTimeWindow: hardestWindowKey.map(WeeklyAggregator.windowDisplayLabel(forKey:)),
            hardestWindowDaysOutOf7: hardestWindowKey.map {
                WeeklyAggregator.windowConsecutiveDays(drifts: weekDrifts, calendar: calendar)[$0] ?? 0
            } ?? 0
        ))

        // 5. 展示字段统一翻译成友好名字。
        let thieves = rawThieves.map {
            TimeThief(rank: $0.rank, label: displayName($0.label), totalSeconds: $0.totalSeconds, snark: $0.snark)
        }
        let chains = DriftChains.topChains(drifts: weekDrifts).map {
            DriftChain(nodes: $0.nodes.map(displayName), count: $0.count, averageSeconds: $0.averageSeconds)
        }

        return RecapData(
            dateLabel: dateLabel,
            deepScore: score,
            narrative: narrative,
            segments: segments,
            heatmap: DriftHeatmap.build(drifts: weekDrifts, calendar: calendar),
            thieves: thieves,
            chains: chains,
            totals: totals
        )
    }
}
