import Foundation

/// 漂移倒计时累加器。每个 1Hz tick 把连续漂移时间往上加，并报告当前 friction 等级。
///
/// **UI / 定时器无关**：真正的 1Hz tick driver（Timer / CADisplayLink）在 App 层，
/// 每个 tick 调用 `tick(_:)`。这样累加与等级映射可以纯逻辑单测。
public final class DriftTracker {

    public private(set) var elapsed: TimeInterval

    public init(elapsed: TimeInterval = 0) {
        self.elapsed = elapsed
    }

    /// 推进 `delta` 秒，返回推进后的 friction 等级。
    @discardableResult
    public func tick(_ delta: TimeInterval) -> FrictionLevel {
        elapsed += max(0, delta)
        return level
    }

    /// 回到绿区 / 拉回时清零。
    public func reset() {
        elapsed = 0
    }

    public var level: FrictionLevel {
        .forElapsed(elapsed)
    }
}
