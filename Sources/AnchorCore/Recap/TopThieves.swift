import Foundation

/// 罪人榜的一行：排名 + 目的地 + 时长 + 自嘲文案（严肃模式下为 nil）。
public struct TimeThief: Equatable, Sendable {
    public let rank: Int
    public let label: String
    public let totalSeconds: Int
    /// 自嘲文案的**本地化 key**（见 `TopThieves.snarkLibrary`），不是译文。
    public let snark: String?

    public init(rank: Int, label: String, totalSeconds: Int, snark: String?) {
        self.rank = rank
        self.label = label
        self.totalSeconds = totalSeconds
        self.snark = snark
    }

    /// 给人看的自嘲文案：查表留到渲染时，所以换语言不用重算罪人榜。
    public var localizedSnark: String? {
        snark.map { L($0) }
    }
}

/// 今日罪人榜聚合（daily-recap-spec §五.3）。
public enum TopThieves {

    /// 自嘲文案库（v1 静态）。
    ///
    /// 存的是**本地化 key，不是译文**。`compute` 用 `index % count` 取梗，
    /// 所以**数组长度本身是有语义的**：如果直接把中文数组换成译文数组，
    /// 某种语言多写或少写一条笑话，同一个名次就会突然换成另一个梗（甚至越界翻页）。
    /// 长度在这里钉死成 6 条，查表推迟到渲染时（`TimeThief.localizedSnark`）。
    ///
    /// 译文不是直译而是**转创**：`摆烂` / `又赢了` 这类梗要在目标语言里重新找一个
    /// 语气对得上的说法——调侃但不刺人。
    public static let snarkLibrary = [
        "thief.snark.0",
        "thief.snark.1",
        "thief.snark.2",
        "thief.snark.3",
        "thief.snark.4",
        "thief.snark.5"
    ]

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
