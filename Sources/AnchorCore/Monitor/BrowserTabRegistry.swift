import Foundation

/// 维护"每个浏览器当前 active tab"的内存状态，并把 NSWorkspace 给的"裸 bundleId 上下文"
/// 补全成带 URL 的上下文（PR #19：tabs 状态合并，以前台浏览器的 active tab 为准）。
///
/// 线程约定：只在主线程访问（daemon 事件由 coordinator 先 hop 到 main）。
public final class BrowserTabRegistry {

    /// 扩展上报的 browser 名 → 可能的 bundle id。
    public static let knownBrowsers: [String: Set<String>] = [
        "chrome": ["com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.canary"],
        "safari": ["com.apple.Safari"],
        "firefox": ["org.mozilla.firefox"],
        "edge": ["com.microsoft.edgemac"],
        "arc": ["company.thebrowser.Browser"],
        "brave": ["com.brave.Browser"]
    ]

    private var activeTab: [String: URL] = [:]

    public init() {}

    public func browserName(forBundleId bundleId: String) -> String? {
        Self.knownBrowsers.first { $0.value.contains(bundleId) }?.key
    }

    public func bundleIds(for browser: String) -> Set<String> {
        Self.knownBrowsers[browser] ?? []
    }

    public func recordActiveTab(browser: String, url: URL) {
        activeTab[browser] = url
    }

    /// 浏览器失焦 / 断连时清掉它的 tab 状态（PR #19）。
    public func clear(browser: String) {
        activeTab[browser] = nil
    }

    public func activeTab(browser: String) -> URL? {
        activeTab[browser]
    }

    /// 若 ctx 是已知浏览器且有已上报的 active tab，则附上 URL；否则原样返回。
    public func enrich(_ ctx: AppContext) -> AppContext {
        guard ctx.url == nil,
              let browser = browserName(forBundleId: ctx.bundleId),
              let url = activeTab[browser] else {
            return ctx
        }
        return AppContext(bundleId: ctx.bundleId, url: url)
    }
}
