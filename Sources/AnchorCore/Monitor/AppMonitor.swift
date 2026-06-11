import Foundation

/// 把"前台 app 变化"这一连串原始输入，转换成去重、带时间戳的 `AnchorEvent` 流。
///
/// **UI 无关**：真正的 `NSWorkspace` 订阅在 AnchorApp 里，拿到通知后喂给本 monitor。
/// 这样"切换 / 去重 / 当前上下文"这套核心逻辑可以用 mock 事件流做单元测试，
/// 不需要拉起 AppKit。
public final class AppMonitor {

    /// 当前前台上下文（最近一次有效变化）。
    public private(set) var current: AppContext?

    /// 最近一次有效变化的时间戳。
    public private(set) var lastChangeAt: Date?

    public init() {}

    /// 记录一次前台变化。
    ///
    /// 若上下文相对上次确实变了（bundleId 或 url 不同），更新 `current` / `lastChangeAt`
    /// 并返回 `.appActivated`；否则返回 `nil`（连续相同的激活会被去重，避免重复打点）。
    @discardableResult
    public func record(bundleId: String, url: URL? = nil, at timestamp: Date) -> AnchorEvent? {
        let ctx = AppContext(bundleId: bundleId, url: url)
        guard ctx != current else { return nil }
        current = ctx
        lastChangeAt = timestamp
        return .appActivated(ctx)
    }

    /// 清空状态（session 结束 / 浏览器失焦时调用）。
    public func reset() {
        current = nil
        lastChangeAt = nil
    }
}
