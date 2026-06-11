import Foundation

/// 根据当前活跃的 Preset，把一个 (app, url) 上下文分类为 green / gray / red。
public struct PresetEngine: Sendable {

    public init() {}

    /// 给定一个 preset 和当前 app context，返回它所在的区。
    /// 优先级：red > green > gray。
    public func classify(_ ctx: AppContext, in preset: Preset) -> ZoneClassification {
        if matches(ctx: ctx, rules: preset.redRules) {
            return .red
        }
        if matches(ctx: ctx, rules: preset.greenRules) {
            return .green
        }
        return .gray
    }

    // MARK: - private

    private func matches(ctx: AppContext, rules: [ZoneRule]) -> Bool {
        for rule in rules {
            if matches(ctx: ctx, rule: rule) {
                return true
            }
        }
        return false
    }

    private func matches(ctx: AppContext, rule: ZoneRule) -> Bool {
        switch rule {
        case .app(let bundleId):
            return ctx.bundleId == bundleId

        case .url(let pattern):
            guard let url = ctx.url else { return false }
            return matchesPattern(url: url, pattern: pattern)
        }
    }

    private func matchesPattern(url: URL, pattern: String) -> Bool {
        URLPatternMatcher.matches(url: url, pattern: pattern)
    }
}

/// 简单的通配符匹配：对 `host + path` 做 `*` → `.*` 的 regex 匹配
/// （query / fragment 不参与，所以 `?page=2`、`#section` 不影响判定）。
/// e.g. `github.com/myorg/*` 匹配 `https://github.com/myorg/anchor`。
/// PresetEngine 与 FocusLock 共用。
public enum URLPatternMatcher {
    public static func matches(url: URL, pattern: String) -> Bool {
        let normalizedURL = (url.host ?? "") + url.path
        let regexPattern = "^" + pattern
            .replacingOccurrences(of: ".", with: "\\.")
            .replacingOccurrences(of: "*", with: ".*")
            + "$"

        guard let regex = try? NSRegularExpression(pattern: regexPattern) else {
            return false
        }
        let range = NSRange(normalizedURL.startIndex..., in: normalizedURL)
        return regex.firstMatch(in: normalizedURL, range: range) != nil
    }
}
