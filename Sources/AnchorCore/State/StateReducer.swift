import Foundation

/// 纯函数状态机。给一个当前状态和一个事件，返回新状态 + 应该产生的副作用。
///
/// 设计原则：
/// - **纯函数**：相同输入必产生相同输出，便于单元测试
/// - **副作用显式**：通过 `SideEffect` 枚举声明，不在 reducer 内部直接执行
/// - **单一信息源**：UI 订阅状态变化，禁止持有本地副本
public struct StateReducer {

    /// 漂移倒计时阈值（秒）。默认 60，可在 Preset 中覆盖。
    public let driftThreshold: TimeInterval

    /// 合法摸鱼时长（秒）。
    public let slackingDuration: TimeInterval

    public init(
        driftThreshold: TimeInterval = 60,
        slackingDuration: TimeInterval = 300
    ) {
        self.driftThreshold = driftThreshold
        self.slackingDuration = slackingDuration
    }

    /// 核心 reduce 函数。
    public func reduce(
        _ state: AnchorState,
        event: AnchorEvent,
        classifier: (AppContext) -> ZoneClassification
    ) -> (AnchorState, [SideEffect]) {
        switch (state, event) {

        // MARK: - app activation
        case let (.green, .appActivated(ctx)):
            return handleAppEnter(ctx, classifier: classifier, previousState: state)

        case let (.drifting(_, _), .appActivated(ctx)):
            return handleAppEnter(ctx, classifier: classifier, previousState: state)

        case let (.red, .appActivated(ctx)):
            return handleAppEnter(ctx, classifier: classifier, previousState: state)

        case let (.offline, .appActivated(ctx)):
            return handleAppEnter(ctx, classifier: classifier, previousState: state)

        // MARK: - drifting tick
        case let (.drifting(elapsed, ctx), .tick(delta)):
            let next = elapsed + delta
            let frictionLevel = frictionCurve(for: next)
            return (.drifting(elapsed: next, currentApp: ctx),
                    [.renderFriction(level: frictionLevel)])

        // MARK: - red zone tick (5-second buffer then friction kicks in)
        case (.red, .tick):
            // For v1 simplicity, red zone applies friction immediately at level 0.5
            // (see dynamic-island-spec.md §II for the full curve).
            return (state, [])

        // MARK: - gestures
        case (_, .islandTapped):
            return (state, [.snapBackToGreen, .playHaptic(.generic), .clearFriction])

        case (_, .islandLongPressed):
            return (.slacking(remaining: slackingDuration),
                    [.clearFriction, .playHaptic(.alignment)])

        case let (_, .islandSwipedUp(reason)):
            return (.paused(reason: reason),
                    [.clearFriction, .writeLog(.init(
                        occurredAt: Date(),
                        from: nil,
                        to: AppContext(bundleId: "system.pause"),
                        durationSeconds: nil
                    ))])

        // MARK: - slacking
        case let (.slacking(remaining), .tick(delta)):
            let next = remaining - delta
            if next <= 0 {
                return (.offline, [.snapBackToGreen, .playHaptic(.levelChange)])
            }
            return (.slacking(remaining: next), [])

        case (.slacking, .slackingTimedOut):
            return (.offline, [.snapBackToGreen, .playHaptic(.levelChange)])

        // MARK: - paused / offline
        case (.paused, .sessionStarted):
            // 恢复看护：回到 offline，下一个 appActivated（coordinator 立即补发）重新分类。
            return (.offline, [.clearFriction])

        case (.paused, _):
            return (state, []) // 其余事件一律吸收，直到显式恢复

        default:
            return (state, [])
        }
    }

    // MARK: - private

    private func handleAppEnter(
        _ ctx: AppContext,
        classifier: (AppContext) -> ZoneClassification,
        previousState: AnchorState
    ) -> (AnchorState, [SideEffect]) {
        switch classifier(ctx) {
        case .green:
            return (.green(currentApp: ctx), [.clearFriction])
        case .gray:
            return (.drifting(elapsed: 0, currentApp: ctx), [])
        case .red:
            return (.red(currentApp: ctx), [.renderFriction(level: 0.5)])
        }
    }

    /// 漂移时间 → friction 强度（0.0–1.0）。
    /// 见 docs/dynamic-island-spec.md §II 的曲线表；分段统一由 `FrictionLevel` 定义。
    private func frictionCurve(for elapsed: TimeInterval) -> Double {
        FrictionLevel.forElapsed(elapsed).blurIntensity
    }
}

/// Preset 引擎给 reducer 的分类结果。
public enum ZoneClassification: Equatable, Sendable {
    case green
    case gray
    case red
}
