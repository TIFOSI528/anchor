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
        let narrative = NarrativeGenerator().generate(input: .init(
            deepMinutes: Double(totals.greenSeconds) / 60,
            longestStreakMinutes: Double(totals.longestStreakSeconds) / 60,
            presetName: presetName,
            driftCount: totals.driftCount,
            topDestination: rawThieves.first.map { displayName($0.label) },
            topDestinationCount: rawThieves.first.map { thief in
                todayDrifts.filter { TopThieves.destinationLabel(for: $0) == thief.label }.count
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
