import Foundation

/// 由"session 起止 + 漂移记录"反推 24h 时间线的区段：
/// 漂移段按其目的地分类成灰/红，漂移之间的空隙即绿区。
///
/// （持久层只存漂移与汇总秒数，不存逐段区间——时间线在读取时重建。）
public enum TimelineBuilder {

    /// - Parameter classify: 给一条漂移记录定区（灰或红），通常用 PresetEngine 包一层。
    public static func intervals(
        sessionStart: Date,
        sessionEnd: Date,
        drifts: [DriftRecord],
        classify: (DriftRecord) -> RecapZone
    ) -> [ZoneInterval] {
        guard sessionEnd > sessionStart else { return [] }

        var intervals: [ZoneInterval] = []
        var cursor = sessionStart

        for drift in drifts.sorted(by: { $0.occurredAt < $1.occurredAt }) {
            let start = max(drift.occurredAt, sessionStart)
            guard start < sessionEnd else { break }
            // duration 缺失（进行中漂移）→ 一直延伸到 session 结束。
            let rawEnd = drift.durationSeconds.map { drift.occurredAt.addingTimeInterval(TimeInterval($0)) } ?? sessionEnd
            let end = min(rawEnd, sessionEnd)
            guard end > start else { continue }

            if start > cursor {
                intervals.append(ZoneInterval(start: cursor, end: start, zone: .green))
            }
            intervals.append(ZoneInterval(start: start, end: end, zone: classify(drift)))
            cursor = max(cursor, end)
        }

        if cursor < sessionEnd {
            intervals.append(ZoneInterval(start: cursor, end: sessionEnd, zone: .green))
        }

        return intervals
    }
}
