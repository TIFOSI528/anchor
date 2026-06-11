import Foundation

/// 一条漂移链：起点 → 中间点 → 终点，附触发次数与平均链路时长。
/// 见 daily-recap-spec §五.4。
public struct DriftChain: Equatable, Sendable {
    public let nodes: [String]
    public let count: Int
    public let averageSeconds: Int

    public init(nodes: [String], count: Int, averageSeconds: Int) {
        self.nodes = nodes
        self.count = count
        self.averageSeconds = averageSeconds
    }
}

/// 从漂移记录里挖掘最常见的漂移路径。
public enum DriftChains {

    /// Top `limit` 条 (起点 → 中间 → 终点) 路径，按触发次数降序。
    /// 只统计三个节点齐全的漂移（有 from、有 next_destination）。
    public static func topChains(drifts: [DriftRecord], limit: Int = 2) -> [DriftChain] {
        struct Aggregate {
            var count = 0
            var totalSeconds = 0
        }

        var aggregates: [[String]: Aggregate] = [:]
        for drift in drifts {
            guard let start = drift.fromURL ?? drift.fromApp,
                  let end = drift.nextDestination else { continue }
            let mid = drift.toURL ?? drift.toApp
            let key = [start, mid, end]
            var aggregate = aggregates[key] ?? Aggregate()
            aggregate.count += 1
            aggregate.totalSeconds += max(0, drift.durationSeconds ?? 0)
            aggregates[key] = aggregate
        }

        return aggregates
            .sorted { lhs, rhs in
                lhs.value.count != rhs.value.count
                    ? lhs.value.count > rhs.value.count
                    : lhs.key.joined() < rhs.key.joined()
            }
            .prefix(limit)
            .map { entry in
                DriftChain(
                    nodes: entry.key,
                    count: entry.value.count,
                    averageSeconds: entry.value.count > 0 ? entry.value.totalSeconds / entry.value.count : 0
                )
            }
    }
}
