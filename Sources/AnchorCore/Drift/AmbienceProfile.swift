import Foundation

/// 一套「漂移时屏幕怎么变」的配方。
///
/// **为什么要抽成数据**：`dynamic-island-spec.md:43-46` 原本设计的灰区曲线是
/// 「边缘 1px 光晕 → 饱和度↓70% → FrictionFog」三层递进，但实现把三档全部塌缩成
/// 同一个全屏模糊（只是 alpha 从 0.1 拉到 0.8）。模糊是唯一一种会**损害可读性**的做法，
/// 和哲学文档引用的 Calm Technology（用余光、不抢注意力）正好相反。
///
/// 把配方变成数据之后：曲线可调、可测试，而且新增一套氛围只是多一份配置——
/// 不需要动渲染代码，也不需要任何付费判断（见 docs/monetization.md）。
public struct AmbienceProfile: Equatable, Sendable, Identifiable {

    /// 曲线上的一个控制点。`intensity` 与 `FrictionLevel.blurIntensity` 对齐
    /// （0 / 0.1 / 0.4 / 0.8），中间值线性插值——红区传的 0.5 因此也能自然落位。
    public struct Stop: Equatable, Sendable {
        /// friction 强度（0–1）。
        public let intensity: Double
        /// 目标饱和度。1 = 原色，0 = 全灰。
        public let saturation: Double
        /// 边缘渐晕强度。0 = 无暗角，1 = 最强。
        public let vignette: Double
        /// 全屏模糊。保留给"怀旧雾"这类配方；calm 配方全程为 0。
        public let blur: Double

        public init(intensity: Double, saturation: Double, vignette: Double, blur: Double) {
            self.intensity = intensity
            self.saturation = saturation
            self.vignette = vignette
            self.blur = blur
        }
    }

    public let id: String
    /// 本地化 key（显示名走 `L(nameKey)`）。
    public let nameKey: String
    /// 本地化 key（一句话说明）。
    public let detailKey: String
    /// 按 intensity 升序排列的控制点。
    public let stops: [Stop]

    public init(id: String, nameKey: String, detailKey: String, stops: [Stop]) {
        self.id = id
        self.nameKey = nameKey
        self.detailKey = detailKey
        self.stops = stops.sorted { $0.intensity < $1.intensity }
    }

    /// 在任意 friction 强度上取样，控制点之间线性插值。
    public func sample(at intensity: Double) -> Stop {
        let clamped = min(max(intensity, 0), 1)
        guard let first = stops.first else {
            return Stop(intensity: clamped, saturation: 1, vignette: 0, blur: 0)
        }
        if clamped <= first.intensity { return first }
        guard let last = stops.last else { return first }
        if clamped >= last.intensity { return last }

        for (lower, upper) in zip(stops, stops.dropFirst()) where clamped <= upper.intensity {
            let span = upper.intensity - lower.intensity
            // 控制点重合时不做除零，直接取上界。
            guard span > 0 else { return upper }
            let t = (clamped - lower.intensity) / span
            return Stop(
                intensity: clamped,
                saturation: lower.saturation + (upper.saturation - lower.saturation) * t,
                vignette: lower.vignette + (upper.vignette - lower.vignette) * t,
                blur: lower.blur + (upper.blur - lower.blur) * t
            )
        }
        return last
    }
}

public extension AmbienceProfile {

    /// 默认配方：世界慢慢褪色 + 暗角向内收。文字全程清晰可读，只走余光通道。
    ///
    /// **数值是按实测可达范围定的，不是照 spec 抄的。** spec 写的是"饱和度↓70%"
    /// （即保留 30%），但跨窗口去饱和的技术地板是**保留约 51%**
    /// （见 `AmbienceRenderer.minimumReachableSaturation` 的实测标定）。
    /// 与其在这里写一个到不了的 0.30、让渲染器悄悄钳掉，不如把真实值写明白，
    /// 并用**更重的暗角**补上顶档该有的分量——那条通道是实测有效的（亮度 151→100）。
    static let calm = AmbienceProfile(
        id: "calm",
        nameKey: "ambience.calm.name",
        detailKey: "ambience.calm.detail",
        stops: [
            .init(intensity: 0.0, saturation: 1.00, vignette: 0.00, blur: 0),
            // 30–60s：只有极淡的暗角，不动颜色。
            .init(intensity: 0.1, saturation: 1.00, vignette: 0.18, blur: 0),
            // 1–3min：颜色开始明显流失（约 -25%）。
            .init(intensity: 0.4, saturation: 0.75, vignette: 0.48, blur: 0),
            // 3min+：压到技术地板 + 暗角吃重。
            .init(intensity: 0.8, saturation: 0.51, vignette: 0.78, blur: 0),
        ]
    )

    /// 只压暗、不动颜色。给"觉得褪色太戏剧化"的人。
    static let dim = AmbienceProfile(
        id: "dim",
        nameKey: "ambience.dim.name",
        detailKey: "ambience.dim.detail",
        stops: [
            .init(intensity: 0.0, saturation: 1.0, vignette: 0.00, blur: 0),
            .init(intensity: 0.1, saturation: 1.0, vignette: 0.22, blur: 0),
            .init(intensity: 0.4, saturation: 1.0, vignette: 0.55, blur: 0),
            .init(intensity: 0.8, saturation: 1.0, vignette: 0.85, blur: 0),
        ]
    )

    /// 0.1.x 的老行为（全屏模糊）。保留给已经习惯它的用户，也方便对照。
    static let fog = AmbienceProfile(
        id: "fog",
        nameKey: "ambience.fog.name",
        detailKey: "ambience.fog.detail",
        stops: [
            .init(intensity: 0.0, saturation: 1.0, vignette: 0, blur: 0.0),
            .init(intensity: 0.1, saturation: 1.0, vignette: 0, blur: 0.1),
            .init(intensity: 0.4, saturation: 1.0, vignette: 0, blur: 0.4),
            .init(intensity: 0.8, saturation: 1.0, vignette: 0, blur: 0.8),
        ]
    )

    /// 内置配方。未来的氛围包只需往这个列表里追加——渲染器不用改。
    static let builtIn: [AmbienceProfile] = [.calm, .dim, .fog]

    static func builtIn(id: String) -> AmbienceProfile? {
        builtIn.first { $0.id == id }
    }
}
