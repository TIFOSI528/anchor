import AppKit
import QuartzCore
import AnchorCore

/// 漂移氛围的渲染器（取代原来的 FrictionFogController）。
///
/// 每块屏幕一个无边框透明窗口，压在系统 shielding 层下面一级。三条独立通道：
///
/// 1. **去饱和** —— 一层灰色 layer，`compositingFilter = "saturationBlendMode"`。
///    该混合模式的语义是"色相与明度取自背景、饱和度取自本层"，所以一层纯灰盖上去
///    就会把**窗口背后的整个屏幕**变灰，靠 layer 不透明度控制程度。
///    关键好处：文字始终清晰可读——模糊做不到这一点。
/// 2. **边缘渐晕** —— 径向渐变，中心透明、四角压黑；随强度加深并且透明核心向内收缩。
///    余光能察觉，视线中心不受干扰（Calm Technology 的做法）。
/// 3. **模糊** —— 只有 `fog` 配方会用到，保留兼容。
///
/// 三条通道的配比由 `AmbienceProfile` 决定，所以换氛围不需要改这里。
@MainActor
final class AmbienceRenderer {

    /// 当前配方。切换后下一次 render 生效。
    var profile: AmbienceProfile = .calm

    /// 用户是否允许屏幕层面的干预（设置里的总开关 + 减少动态效果）。
    var isEnabled: () -> Bool = { true }

    private var screens: [ScreenLayer] = []
    private var currentIntensity: Double = 0

    /// 一块屏幕对应的一组图层。
    private final class ScreenLayer {
        let window: NSWindow
        let desaturate: CALayer
        let vignette: CAGradientLayer
        let blur: NSVisualEffectView

        init(window: NSWindow, desaturate: CALayer, vignette: CAGradientLayer, blur: NSVisualEffectView) {
            self.window = window
            self.desaturate = desaturate
            self.vignette = vignette
            self.blur = blur
        }
    }

    // MARK: - public

    func render(level intensity: Double) {
        guard isEnabled(), intensity > 0 else {
            clear()
            return
        }
        ensureWindows()
        currentIntensity = intensity
        let stop = effectiveStop(at: intensity)
        apply(stop, animated: !reduceMotion)
    }

    func clear() {
        guard currentIntensity > 0 || !screens.isEmpty else { return }
        currentIntensity = 0
        let cleared = AmbienceProfile.Stop(intensity: 0, saturation: 1, vignette: 0, blur: 0)
        apply(cleared, animated: !reduceMotion)
        // 等淡出结束再撤窗口，否则会看到一次突兀的跳变。
        let delay = reduceMotion ? 0 : 0.22
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.currentIntensity == 0 else { return }
                for screen in self.screens { screen.window.orderOut(nil) }
                self.screens.removeAll()
            }
        }
    }

    /// 让用户在设置里**当场看一眼**某个配方（无法凭文字判断氛围）。
    /// 直接按目标强度渲染一段时间，然后恢复当前真实状态。
    func preview(profile previewProfile: AmbienceProfile, intensity: Double, seconds: Double) {
        let restoreProfile = profile
        let restoreIntensity = currentIntensity
        profile = previewProfile
        render(level: intensity)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.profile = restoreProfile
                if restoreIntensity > 0 {
                    self.render(level: restoreIntensity)
                } else {
                    self.clear()
                }
            }
        }
    }

    // MARK: - private

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// 取样后再按系统无障碍设置收一收。
    private func effectiveStop(at intensity: Double) -> AmbienceProfile.Stop {
        let stop = profile.sample(at: intensity)
        guard NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency else { return stop }
        // 开了「降低透明度」的人最不能承受遮挡，而 .behindWindow 的 vibrancy 在那种设置下
        // 会退化成不透明填充——所以把模糊和暗角都压低，去饱和不受影响（它不是透明度效果）。
        return AmbienceProfile.Stop(
            intensity: stop.intensity,
            saturation: stop.saturation,
            vignette: min(stop.vignette, 0.35),
            blur: min(stop.blur, 0.45)
        )
    }

    private func apply(_ stop: AmbienceProfile.Stop, animated: Bool) {
        let duration = animated ? 0.22 : 0
        // 饱和度 s 需要的灰层不透明度就是 1 - s。
        let desaturateOpacity = Float(min(max(1 - stop.saturation, 0), 1))

        CATransaction.begin()
        CATransaction.setAnimationDuration(duration)
        CATransaction.setDisableActions(!animated)
        for screen in screens {
            screen.desaturate.opacity = desaturateOpacity
            screen.vignette.opacity = Float(stop.vignette)
            // 暗角不只是变深，透明核心还向内收缩——像视野在变窄。
            let core = 0.62 - 0.30 * stop.vignette
            screen.vignette.locations = [NSNumber(value: max(core, 0.05)), 1.0]
            screen.blur.alphaValue = CGFloat(stop.blur)
            screen.blur.isHidden = stop.blur <= 0.001
        }
        CATransaction.commit()
    }

    private func ensureWindows() {
        if screens.count != NSScreen.screens.count {
            for screen in screens { screen.window.orderOut(nil) }
            screens = NSScreen.screens.map(makeScreenLayer(for:))
            for screen in screens { screen.window.orderFrontRegardless() }
        }
    }

    private func makeScreenLayer(for screen: NSScreen) -> ScreenLayer {
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) - 1)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        // 窗口整体保持全不透明，各通道各自控制自己的 opacity——
        // 否则窗口 alpha 会把三条通道乘在一起，调不准。
        window.alphaValue = 1

        let root = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        root.wantsLayer = true
        root.autoresizingMask = [.width, .height]
        guard let rootLayer = root.layer else {
            // 理论上 wantsLayer 之后必有 layer；真拿不到就退化成空窗口而不是崩。
            window.contentView = root
            return ScreenLayer(window: window, desaturate: CALayer(),
                               vignette: CAGradientLayer(), blur: NSVisualEffectView())
        }

        // 1) 模糊（只有 fog 配方用；默认隐藏）
        let blur = NSVisualEffectView(frame: root.bounds)
        blur.material = .fullScreenUI
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.autoresizingMask = [.width, .height]
        blur.alphaValue = 0
        blur.isHidden = true
        root.addSubview(blur)

        // 2) 去饱和：纯灰 + saturationBlendMode，对窗口背后生效
        let desaturate = CALayer()
        desaturate.frame = rootLayer.bounds
        desaturate.backgroundColor = NSColor(white: 0.5, alpha: 1).cgColor
        desaturate.compositingFilter = "saturationBlendMode"
        desaturate.opacity = 0
        desaturate.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        rootLayer.addSublayer(desaturate)

        // 3) 边缘渐晕：径向渐变，中心透明、四周压黑
        let vignette = CAGradientLayer()
        vignette.frame = rootLayer.bounds
        vignette.type = .radial
        vignette.colors = [
            NSColor.black.withAlphaComponent(0).cgColor,
            NSColor.black.withAlphaComponent(0.92).cgColor,
        ]
        vignette.locations = [0.62, 1.0]
        // 径向渐变从中心铺到角落（0.5,0.5 → 1,1 覆盖对角）。
        vignette.startPoint = CGPoint(x: 0.5, y: 0.5)
        vignette.endPoint = CGPoint(x: 1, y: 1)
        vignette.opacity = 0
        vignette.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        rootLayer.addSublayer(vignette)

        window.contentView = root
        return ScreenLayer(window: window, desaturate: desaturate, vignette: vignette, blur: blur)
    }
}
