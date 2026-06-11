import Foundation

/// 复盘触发时间计算：每日 22:00 敲门 + 每周日 21:00 周回顾。
/// 纯函数，App 层拿到日期后用 Timer 调度。
public enum RecapScheduler {

    /// 下一个"每天 hour:minute"的时刻（严格在 `date` 之后）。
    public static func nextDaily(
        hour: Int,
        minute: Int = 0,
        after date: Date,
        calendar: Calendar = .current
    ) -> Date {
        calendar.nextDate(
            after: date,
            matching: DateComponents(hour: hour, minute: minute),
            matchingPolicy: .nextTime
        ) ?? date.addingTimeInterval(86_400)
    }

    /// 下一个"每周 weekday hour:minute"的时刻。`weekday` 用 Calendar 语义：1=周日…7=周六。
    public static func nextWeekly(
        weekday: Int,
        hour: Int,
        minute: Int = 0,
        after date: Date,
        calendar: Calendar = .current
    ) -> Date {
        calendar.nextDate(
            after: date,
            matching: DateComponents(hour: hour, minute: minute, weekday: weekday),
            matchingPolicy: .nextTime
        ) ?? date.addingTimeInterval(7 * 86_400)
    }
}
