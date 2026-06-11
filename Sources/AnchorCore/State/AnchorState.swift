import Foundation

/// 当前 Anchor session 的状态。
///
/// 这是产品的单一信息源（single source of truth）。所有 UI 都应订阅
/// 这个状态的变化，禁止任何组件持有自己的"本地状态副本"。
public enum AnchorState: Equatable {
    /// 在白名单中。灵动岛几乎隐形。
    case green(currentApp: AppContext)

    /// 漂移中（已离开绿区）。`elapsed` 是连续漂移秒数。
    case drifting(elapsed: TimeInterval, currentApp: AppContext)

    /// 在黑名单中。立即 friction。
    case red(currentApp: AppContext)

    /// 用户长按灵动岛承认"我就是要摸鱼"。`remaining` 是剩余合法摸鱼秒数。
    case slacking(remaining: TimeInterval)

    /// 用户向上划走暂停 session。`reason` 是被强制输入的理由。
    case paused(reason: String)

    /// 无活跃 session。
    case offline
}

/// 描述当前活跃的 app 上下文：bundle id + 可选的浏览器 tab URL。
public struct AppContext: Equatable, Hashable {
    public let bundleId: String
    public let url: URL?

    public init(bundleId: String, url: URL? = nil) {
        self.bundleId = bundleId
        self.url = url
    }
}

/// 触发状态变化的事件。
public enum AnchorEvent {
    case appActivated(AppContext)
    case tabChanged(browser: String, url: URL)
    case tick(deltaSeconds: TimeInterval)
    case islandTapped
    case islandLongPressed
    case islandSwipedUp(reason: String)
    case presetSwitched(presetId: String)
    case slackingTimedOut
    case sessionStarted
    case sessionEnded
}

/// 状态变化产生的副作用。Reducer 显式声明这些 effect 而不直接执行，
/// 保证 reducer 是纯函数、可测试。
public enum SideEffect: Equatable {
    case snapBackToGreen
    case renderFriction(level: Double)
    case clearFriction
    case playHaptic(HapticType)
    case writeLog(DriftLogEntry)
    case sendNotification(String)
    case showRecap
}

public enum HapticType: Equatable {
    case alignment
    case levelChange
    case generic
}

public struct DriftLogEntry: Equatable {
    public let occurredAt: Date
    public let from: AppContext?
    public let to: AppContext
    public let durationSeconds: TimeInterval?

    public init(
        occurredAt: Date,
        from: AppContext?,
        to: AppContext,
        durationSeconds: TimeInterval?
    ) {
        self.occurredAt = occurredAt
        self.from = from
        self.to = to
        self.durationSeconds = durationSeconds
    }
}
