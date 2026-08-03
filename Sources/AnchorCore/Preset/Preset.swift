import Foundation

/// 一个 Preset 代表用户预定义的工作场景，例如"写代码"、"读资料"。
///
/// 每个 Preset 有自己的白名单 / 黑名单规则，灰区为"未分类"自动 fallback。
public struct Preset: Identifiable, Equatable, Sendable {
    public let id: String
    /// 持久化的名字（写进 presets 表）。展示请用 `displayName`，别直接用它。
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

    /// 给人看的名字。**展示一律走这里，不要直接用 `name`。**
    ///
    /// 内置场景的 `name` 会在首次启动时被写进 SQLite（`PresetLibrary.loadOrSeed`），
    /// 那一刻当时的语言就被**冻在库里**了：用户之后改系统语言，DB 里那一行还是老语言，
    /// 永远不会重新翻译。所以这里不看 `name`，而是用**稳定的 `id`** 反查内置场景的
    /// 本地化 key，查表推迟到渲染时——老库里的行也能跟着语言变。
    ///
    /// 用户自建的场景没有内置 key，回落到用户自己输入的 `name`（那本来就不该被翻译）。
    public var displayName: String {
        BuiltinPresets.localizedName(forId: id) ?? name
    }

    /// 只观察、不干预。
    ///
    /// 没有任何绿区规则时，「所有 app 都是灰区」——此时施加 friction 是纯粹的骚扰：
    /// 橡皮筋的另一端没有系在任何东西上。这类场景（如内置「随便看看」、或用户刚新建
    /// 还没填规则的空场景）只记录数据、显示状态，不糊屏幕、不锁滚动。
    public var isObserveOnly: Bool { greenRules.isEmpty }
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
///
/// 三个内置场景名的持久化身份是 `id`（`builtin.write-code` …），名字只是展示。
/// 这里用 `static var` 而不是 `static let`：`L()` 的查表跟着系统语言，
/// 用 `let` 会在进程第一次访问时就把译文冻住。
public enum BuiltinPresets {

    /// 内置场景 id → 名字的本地化 key。
    ///
    /// 有了这张表，`Preset.displayName` 才能只靠 `id` 就还原出当前语言的名字，
    /// 不必相信 DB 里那个可能是几个月前、另一种语言写进去的 `name`。
    private static let nameKeys = [
        "builtin.write-code": "preset.builtin.write_code",
        "builtin.read-docs": "preset.builtin.read_docs",
        "builtin.casual": "preset.builtin.casual"
    ]

    /// 内置场景当前语言的名字；`id` 不是内置场景时返回 nil（由调用方回落）。
    public static func localizedName(forId id: String) -> String? {
        nameKeys[id].map { L($0) }
    }

    public static var writeCode: Preset { Preset(
        id: "builtin.write-code",
        name: L("preset.builtin.write_code"),
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
    ) }

    public static var readDocs: Preset { Preset(
        id: "builtin.read-docs",
        name: L("preset.builtin.read_docs"),
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
    ) }

    public static var casualMode: Preset { Preset(
        id: "builtin.casual",
        name: L("preset.builtin.casual"),
        greenRules: [], // 全部 fallback 到灰区
        redRules: []   // 不主动拦截，只做统计
    ) }

    public static var all: [Preset] { [writeCode, readDocs, casualMode] }
}
