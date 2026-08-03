import Foundation

/// 「哪一天」的稳定标识。
///
/// **为什么需要单独一个类型**：`yyyy-MM-dd` 看着人畜无害，但用裸 `DateFormatter` 生成时
/// 会继承用户 locale 的**日历系统与数字系统**。泰语环境（佛历）下今天是 `2569-06-20`，
/// 沙特环境（回历 + 阿拉伯数字）下是 `١٤٤٧-٠٦-٢٠`。
///
/// 而这个字符串被当成两处的主键：
/// - `daily_recaps.date TEXT PRIMARY KEY`
/// - 摸鱼日计数器的跨天判断（`SlackingCounter`）
///
/// 所以用户一改语言/地区，复盘表就会被重新 key 一遍（历史复盘"消失"），日计数也会被误重置。
/// 这里把**存储用的 key** 钉死成 ISO-8601 + `en_US_POSIX`，与 locale 完全脱钩；
/// 需要给人看的时候走 `displayLabel`，那边才跟随 locale。
public enum DayKey {

    /// 存储/比较用的稳定 key：`2026-08-03`，永远是 ISO 日历与 ASCII 数字。
    public static func key(for date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    /// 把稳定 key 还原成 `Date`（用于把 key 转成本地化显示文案）。
    public static func date(fromKey key: String, timeZone: TimeZone = .current) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: key)
    }

    /// 给人看的日期文案：跟随用户 locale 与日历（中文「2026年8月3日」/ 英文「Aug 3, 2026」）。
    public static func displayLabel(forKey key: String, locale: Locale = .current) -> String {
        guard let date = date(fromKey: key) else { return key }
        return date.formatted(.dateTime.year().month(.abbreviated).day().locale(locale))
    }
}
