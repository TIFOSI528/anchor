import Foundation

/// Deep Score 计算器。**公式公开、可被用户审查**。
///
/// 公式（见 docs/daily-recap-spec.md §III）：
/// ```
/// raw_score = (绿区分钟 × 1.0) + (灰区分钟 × 0.3) - (红区分钟 × 1.5) - (漂移次数 × 0.5)
/// normalized = clamp(raw_score / 在线总分钟, 0, 1) × 100
/// ```
public struct DeepScore {

    public struct Input {
        public let greenMinutes: Double
        public let grayMinutes: Double
        public let redMinutes: Double
        public let driftCount: Int

        public init(greenMinutes: Double, grayMinutes: Double, redMinutes: Double, driftCount: Int) {
            self.greenMinutes = greenMinutes
            self.grayMinutes = grayMinutes
            self.redMinutes = redMinutes
            self.driftCount = driftCount
        }

        public var onlineMinutes: Double {
            greenMinutes + grayMinutes + redMinutes
        }
    }

    public struct Weights: Sendable {
        public var green: Double
        public var gray: Double
        public var red: Double
        public var driftPenalty: Double

        public static let `default` = Weights(green: 1.0, gray: 0.3, red: -1.5, driftPenalty: -0.5)

        public init(green: Double, gray: Double, red: Double, driftPenalty: Double) {
            self.green = green
            self.gray = gray
            self.red = red
            self.driftPenalty = driftPenalty
        }
    }

    public let weights: Weights

    public init(weights: Weights = .default) {
        self.weights = weights
    }

    /// 计算 0–100 的归一化 score。
    public func compute(input: Input) -> Int {
        guard input.onlineMinutes > 0 else { return 0 }

        let raw = input.greenMinutes * weights.green
                + input.grayMinutes * weights.gray
                + input.redMinutes * weights.red
                + Double(input.driftCount) * weights.driftPenalty

        let normalized = max(0, min(1, raw / input.onlineMinutes))
        return Int(normalized * 100)
    }
}
