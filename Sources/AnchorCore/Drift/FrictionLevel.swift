import Foundation

/// 漂移深度的离散等级。驱动灵动岛形态与 FrictionFog 的 blur 强度。
///
/// 时间分段见 dynamic-island-spec §II：0–30s 无感，30–60s 轻微，1–3min 中度，3min+ 重度。
public enum FrictionLevel: Int, Sendable, CaseIterable, Comparable {
    case none = 0
    case subtle = 1
    case moderate = 2
    case heavy = 3

    public static func < (lhs: FrictionLevel, rhs: FrictionLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// 曲线的基准阈值。默认档（60s）下分段就是 spec 原文的 30 / 60 / 180。
    public static let referenceThreshold: TimeInterval = 60

    /// 连续漂移秒数 → friction 等级。
    ///
    /// `threshold` = 用户在场景里设的「漂移倒计时」。整条曲线按 `threshold / 60` 等比缩放，
    /// 所以这个滑杆是**真的**在调节节奏，而不只是改圆环填充速度：
    /// 设 300s 时，轻微 friction 要 150s 才出现、最重档要 15 分钟。
    ///
    /// （此前 `driftThreshold` 被 reducer 存着但从不读取，曲线恒为 30/60/180。）
    public static func forElapsed(
        _ seconds: TimeInterval,
        threshold: TimeInterval = FrictionLevel.referenceThreshold
    ) -> FrictionLevel {
        let scale = max(threshold, 1) / referenceThreshold
        switch seconds {
        case ..<(30 * scale): return .none
        case ..<(60 * scale): return .subtle
        case ..<(180 * scale): return .moderate
        default: return .heavy
        }
    }

    /// 归一化 blur 强度（0.0–1.0），FrictionFog 用它驱动高斯模糊半径。
    public var blurIntensity: Double {
        switch self {
        case .none: return 0.0
        case .subtle: return 0.1
        case .moderate: return 0.4
        case .heavy: return 0.8
        }
    }
}
