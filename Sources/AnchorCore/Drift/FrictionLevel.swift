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

    /// 连续漂移秒数 → friction 等级。
    public static func forElapsed(_ seconds: TimeInterval) -> FrictionLevel {
        switch seconds {
        case ..<30: return .none
        case ..<60: return .subtle
        case ..<180: return .moderate
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
