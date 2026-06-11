import Foundation

/// 维护"最近 N 个绿区 app"的 MRU 栈。单击灵动岛拉回时切到栈顶。
///
/// 见 mvp-roadmap PR #12：栈空时调用方应显示 hint 而不是报错。
public final class LastGreenAppTracker {

    public let capacity: Int

    /// 最近在前（index 0 = 最近一次的绿区 app）。
    public private(set) var apps: [AppContext] = []

    public init(capacity: Int = 5) {
        self.capacity = max(1, capacity)
    }

    /// 记录一次绿区命中。重复 app 会被移到栈顶；超出容量丢弃最旧的。
    public func record(_ ctx: AppContext) {
        apps.removeAll { $0 == ctx }
        apps.insert(ctx, at: 0)
        if apps.count > capacity {
            apps.removeLast(apps.count - capacity)
        }
    }

    /// 单击拉回目标：最近一个绿区 app。栈空返回 nil（调用方显示 hint）。
    public var snapBackTarget: AppContext? {
        apps.first
    }

    public func reset() {
        apps.removeAll()
    }
}
