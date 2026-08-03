import AppKit
import AnchorCore

/// 全屏 FrictionFog（PR #14/#15）：每个 Display 一个覆盖窗口，
/// `NSVisualEffectView(.behindWindow)` 做系统级背景模糊 + 灰度遮罩，
/// 强度由 friction level（0–1）连续驱动，清除时 200ms ease-out。
///
/// 行为约束：
/// - `ignoresMouseEvents = true`——fog 是"让你注意到"，绝不锁死交互
/// - Settings 关掉 friction / 开启"减少 friction"时一律不渲染（Accessibility 底线）
@MainActor
final class FrictionFogController {

    private var windows: [NSWindow] = []
    private var currentLevel: Double = 0

    var isEnabled: () -> Bool = { true }

    /// 顶格不透明度。系统开了「降低透明度」时压到更低——
    /// `.behindWindow` 的 vibrancy 在那种设置下会退化成不透明填充，
    /// 于是最不能承受遮挡的用户反而得到最实的一层雾。这是反了的。
    private var maximumAlpha: Double {
        NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency ? 0.45 : 1.0
    }

    func render(level: Double) {
        guard isEnabled(), level > 0 else {
            clear()
            return
        }
        ensureWindows()
        let capped = min(level, maximumAlpha)
        currentLevel = capped
        // 「减少动态效果」时不做淡入，直接到位。
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? 0 : 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            for window in windows {
                window.animator().alphaValue = CGFloat(capped)
            }
        }
    }

    func clear() {
        guard currentLevel > 0 || !windows.isEmpty else { return }
        currentLevel = 0
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            for window in windows {
                window.animator().alphaValue = 0
            }
        }, completionHandler: {
            Task { @MainActor [weak self] in
                guard let self, self.currentLevel == 0 else { return }
                for window in self.windows { window.orderOut(nil) }
                self.windows.removeAll()
            }
        })
    }

    // MARK: - private

    private func ensureWindows() {
        guard windows.isEmpty else {
            syncToScreens()
            return
        }
        windows = NSScreen.screens.map(makeWindow(for:))
        for window in windows {
            window.alphaValue = 0
            window.orderFrontRegardless()
        }
    }

    private func syncToScreens() {
        if windows.count != NSScreen.screens.count {
            for window in windows { window.orderOut(nil) }
            windows = NSScreen.screens.map(makeWindow(for:))
            for window in windows {
                window.alphaValue = CGFloat(currentLevel)
                window.orderFrontRegardless()
            }
        }
    }

    private func makeWindow(for screen: NSScreen) -> NSWindow {
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

        let blur = NSVisualEffectView(frame: NSRect(origin: .zero, size: screen.frame.size))
        blur.material = .fullScreenUI
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.autoresizingMask = [.width, .height]

        let dim = NSView(frame: blur.bounds)
        dim.wantsLayer = true
        dim.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.18).cgColor
        dim.autoresizingMask = [.width, .height]
        blur.addSubview(dim)

        window.contentView = blur
        return window
    }
}
