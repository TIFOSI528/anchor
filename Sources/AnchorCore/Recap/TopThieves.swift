import Foundation

/// 罪人榜的一行：排名 + 目的地 + 时长 + 自嘲文案（严肃模式下为 nil）。
public struct TimeThief: Equatable, Sendable {
    public let rank: Int
    public let label: String
    public let totalSeconds: Int
    public let snark: String?

    public init(rank: Int, label: String, totalSeconds: Int, snark: String?) {
        self.rank = rank
        self.label = label
        self.totalSeconds = totalSeconds
        self.snark = snark
    }
}

/// 今日罪人榜聚合（daily-recap-spec §五.3）。
public enum TopThieves {

    /// 自嘲文案库（v1 静态）。
    public static let snarkLibrary = ["又赢了", "假装在学习", "摆烂", "意料之中", "今日 boss", "稳定输出"]

    /// Deep Score 低于此值自动切严肃模式，不显示自嘲文案。
    public static let seriousModeScoreThreshold = 30

    /// 一条漂移的"目的地"标签：有 URL 取 host，否则取 app bundle id。
    public static func destinationLabel(for drift: DriftRecord) -> String {
        if let urlString = drift.toURL, let host = URL(string: urlString)?.host {
            return host
        }
        return drift.toApp
    }

    /// 按目的地汇总停留时长，取 Top `limit`。
    /// 严肃模式（显式开启或 deepScore < 30）下不附自嘲文案。
    public static func compute(
        drifts: [DriftRecord],
        deepScore: Int,
        seriousMode: Bool = false,
        limit: Int = 3
    ) -> [TimeThief] {
        guard !drifts.isEmpty else { return [] }

        var totals: [String: Int] = [:]
        for drift in drifts {
            totals[destinationLabel(for: drift), default: 0] += max(0, drift.durationSeconds ?? 0)
        }

        let serious = seriousMode || deepScore < seriousModeScoreThreshold

        // 时长降序；并列时按 label 升序，保证结果稳定可测。
        let ranked = totals
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(limit)

        return ranked.enumerated().map { index, entry in
            TimeThief(
                rank: index + 1,
                label: entry.key,
                totalSeconds: entry.value,
                snark: serious ? nil : snarkLibrary[index % snarkLibrary.count]
            )
        }
    }
}
