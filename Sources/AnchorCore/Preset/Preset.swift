import Foundation

/// 一个 Preset 代表用户预定义的工作场景，例如"写代码"、"读资料"。
///
/// 每个 Preset 有自己的白名单 / 黑名单规则，灰区为"未分类"自动 fallback。
public struct Preset: Identifiable, Equatable, Sendable {
    public let id: String
    public var name: String
    public var greenRules: [ZoneRule]
    public var redRules: [ZoneRule]
    /// 漂移倒计时阈值（秒），默认 60。
    public var driftThresholdSeconds: TimeInterval

    public init(
        id: String,
        name: String,
        greenRules: [ZoneRule] = [],
        redRules: [ZoneRule] = [],
        driftThresholdSeconds: TimeInterval = 60
    ) {
        self.id = id
        self.name = name
        self.greenRules = greenRules
        self.redRules = redRules
        self.driftThresholdSeconds = driftThresholdSeconds
    }
}

/// 一条规则。可以是 app bundle id，也可以是 URL pattern。
public enum ZoneRule: Equatable, Sendable {
    case app(bundleId: String)
    case url(pattern: String) // 支持 `*` 通配符
}

extension Preset {
    /// 把一个 app 收编进指定区，返回新 preset（一键收编的互斥语义，唯一实现处）。
    ///
    /// - 加绿自动移红、加红自动移绿；`.gray` = 从两边移除（放回灰区）
    /// - 只作用于 `.app` 精确规则，url 规则不受影响
    public func capturing(bundleId: String, as zone: ZoneClassification) -> Preset {
        capturing(rule: .app(bundleId: bundleId), as: zone)
    }

    /// url 版收编（前台是浏览器且已知 tab 时，收编站点而不是整个浏览器）。
    /// 互斥只作用于完全相同的 pattern，不碰其它 url / app 规则。
    public func capturing(urlPattern: String, as zone: ZoneClassification) -> Preset {
        capturing(rule: .url(pattern: urlPattern), as: zone)
    }

    /// 该 app 当前在哪个名单（nil = 未列入，走灰区兜底）。红优先，与引擎判定一致。
    public func membership(ofApp bundleId: String) -> ZoneClassification? {
        membership(of: .app(bundleId: bundleId))
    }

    /// 该 url pattern 当前在哪个名单（精确比对 pattern 字符串，不做通配展开）。
    public func membership(ofURLPattern pattern: String) -> ZoneClassification? {
        membership(of: .url(pattern: pattern))
    }

    // MARK: - private

    private func capturing(rule: ZoneRule, as zone: ZoneClassification) -> Preset {
        var copy = self
        copy.greenRules.removeAll { $0 == rule }
        copy.redRules.removeAll { $0 == rule }
        switch zone {
        case .green: copy.greenRules.append(rule)
        case .red: copy.redRules.append(rule)
        case .gray: break
        }
        return copy
    }

    private func membership(of rule: ZoneRule) -> ZoneClassification? {
        if redRules.contains(rule) { return .red }
        if greenRules.contains(rule) { return .green }
        return nil
    }
}

/// 内置的默认 presets。首次启动时自动安装。
public enum BuiltinPresets {

    public static let writeCode = Preset(
        id: "builtin.write-code",
        name: "写代码",
        greenRules: [
            .app(bundleId: "com.microsoft.VSCode"),
            .app(bundleId: "com.apple.Terminal"),
            .app(bundleId: "com.googlecode.iterm2"),
            .app(bundleId: "com.mitchellh.ghostty"),
            .url(pattern: "github.com/*"),
            .url(pattern: "stackoverflow.com/*"),
            .url(pattern: "developer.apple.com/*")
        ],
        redRules: [
            .url(pattern: "twitter.com/home"),
            .url(pattern: "x.com/home"),
            .url(pattern: "youtube.com/feed/*"),
            .url(pattern: "youtube.com/"),
            .url(pattern: "github.com/trending*")
        ]
    )

    public static let readDocs = Preset(
        id: "builtin.read-docs",
        name: "读资料",
        greenRules: [
            .app(bundleId: "com.apple.Preview"),
            .app(bundleId: "md.obsidian"),
            .app(bundleId: "net.shinyfrog.bear"),
            .url(pattern: "arxiv.org/*"),
            .url(pattern: "scholar.google.com/*")
        ],
        redRules: [
            .url(pattern: "twitter.com/home"),
            .url(pattern: "x.com/home"),
            .url(pattern: "xiaohongshu.com/*"),
            .url(pattern: "bilibili.com/*")
        ]
    )

    public static let casualMode = Preset(
        id: "builtin.casual",
        name: "随便看看",
        greenRules: [], // 全部 fallback 到灰区
        redRules: []   // 不主动拦截，只做统计
    )

    public static let all: [Preset] = [writeCode, readDocs, casualMode]
}
