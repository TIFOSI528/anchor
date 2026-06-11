import Foundation

/// "只看这个"临时锁定：一次性的单目标会话（设计稿
/// docs/plans/2026-06-10-focus-lock-design.md）。
///
/// 不是 preset——不持久化、不进 preset 列表，作为 classifier overlay 临时
/// 替换分类逻辑：**锁内 → 绿；preset 红名单照常红；其余一切（含平时的绿区）→ 灰**。
public struct FocusLock: Equatable, Sendable {

    public enum Target: Equatable, Sendable {
        /// 锁整个 app（PDF 阅读器等本地场景；锁到具体文档需 AX 权限，v1.1）。
        case app(bundleId: String)
        /// 锁 URL 前缀（页面锁 `host/path*` 或站点锁 `host/*`）。
        case urlPrefix(pattern: String)
    }

    public let target: Target
    /// 展示用标签（菜单 / 灵动岛 hint）。
    public let label: String

    public init(target: Target, label: String) {
        self.target = target
        self.label = label
    }

    public func allows(_ ctx: AppContext) -> Bool {
        switch target {
        case .app(let bundleId):
            return ctx.bundleId == bundleId
        case .urlPrefix(let pattern):
            guard let url = ctx.url else { return false }
            return URLPatternMatcher.matches(url: url, pattern: pattern)
        }
    }

    /// 锁定期间的分类：锁 > 红 > 灰（用户当下明确声明的意图盖过一切；
    /// 已知时间黑洞照常拦；平时的绿区也压成灰）。
    public func classify(_ ctx: AppContext, preset: Preset, engine: PresetEngine) -> ZoneClassification {
        if allows(ctx) { return .green }
        return engine.classify(ctx, in: preset) == .red ? .red : .gray
    }

    // MARK: - 由当前上下文构造

    /// 页面锁：`host/path*`。路径为空/根路径时退化为站点锁。
    public static func page(for url: URL, bundleId: String) -> FocusLock? {
        guard let host = url.host else { return nil }
        let path = url.path
        if path.isEmpty || path == "/" {
            return site(for: url, bundleId: bundleId)
        }
        let trimmed = path.hasSuffix("/") ? String(path.dropLast()) : path
        return FocusLock(target: .urlPrefix(pattern: host + trimmed + "*"), label: host + trimmed)
    }

    /// 站点锁：`host/*`。
    public static func site(for url: URL, bundleId: String) -> FocusLock? {
        guard let host = url.host else { return nil }
        return FocusLock(target: .urlPrefix(pattern: host + "/*"), label: host)
    }

    /// app 锁。
    public static func app(bundleId: String, name: String) -> FocusLock {
        FocusLock(target: .app(bundleId: bundleId), label: name)
    }
}
