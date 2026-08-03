import Foundation

/// 合法摸鱼的软/硬上限（dynamic-island-spec §四 手势 2）：
/// 每天前 3 次为软上限——5 分钟到点时再问一次"还要 5 分钟吗？"；
/// 第 4 次起为硬上限——到点强制拉回，不再询问。日计数 00:00 重置。
public struct SlackingPolicy: Sendable {

    public enum Mode: Equatable, Sendable {
        /// 到点询问是否续期。
        case soft
        /// 到点强制拉回。
        case hard
    }

    public let softLimitPerDay: Int

    public init(softLimitPerDay: Int = 3) {
        self.softLimitPerDay = softLimitPerDay
    }

    /// `usedToday` = 今天已经用过的摸鱼次数（本次之前）。
    public func mode(usedToday: Int) -> Mode {
        usedToday < softLimitPerDay ? .soft : .hard
    }
}

/// 跨天自动归零的摸鱼日计数器。`dayKey` 可注入，便于测试。
public final class SlackingCounter {

    private var count = 0
    private var day: String
    private let dayKey: () -> String

    public init(dayKey: @escaping () -> String = SlackingCounter.systemDayKey) {
        self.dayKey = dayKey
        self.day = dayKey()
    }

    /// 用 locale 无关的稳定 key（见 `DayKey`）——否则改一次系统语言/地区就会误清零日计数。
    public static let systemDayKey: @Sendable () -> String = {
        DayKey.key(for: Date())
    }

    /// 当前已用次数（自动处理跨天清零）。
    public var usedToday: Int {
        rolloverIfNeeded()
        return count
    }

    /// 记一次摸鱼，返回记完后的累计。
    @discardableResult
    public func increment() -> Int {
        rolloverIfNeeded()
        count += 1
        return count
    }

    private func rolloverIfNeeded() {
        let today = dayKey()
        if today != day {
            day = today
            count = 0
        }
    }
}
