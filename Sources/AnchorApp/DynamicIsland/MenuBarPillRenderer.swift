import AppKit
import SwiftUI
import Combine

/// 自研「菜单栏嵌入」后端（docs/plans/2026-06-11-menubar-pill-design.md）。
///
/// 解决无刘海屏的遮挡问题：不画 300pt 假刘海黑块，而是一个**宽度=内容**的胶囊
/// 嵌在菜单栏中段——休眠只占一个小圆点且**点击穿透**（系统状态图标照常可点），
/// 漂移展开才变宽、才接收手势。
///
/// 窗口配置对齐 open-vibe-island 的已验证做法：borderless NSPanel、`.statusBar` 层级、
/// 默认 `ignoresMouseEvents = true`、`[.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]`。
@MainActor
final class MenuBarPillRenderer {

    /// 摆放方式。
    enum Placement {
        /// 菜单栏正中（无刘海屏的主后端）：空闲点击穿透。
        case menuBarCenter
        /// 贴在硬件刘海左侧（真刘海屏的绿区点）：零覆盖、可点击开菜单。
        case besideNotch
    }

    private let model: IslandViewModel
    private let placement: Placement
    private var panel: NSPanel?
    private var hosting: NSHostingView<MenuBarPillRoot>?
    private var modelObserver: AnyCancellable?
    private var screenObserver: NSObjectProtocol?
    private var level: IslandController.Level = .hidden

    init(model: IslandViewModel, placement: Placement = .menuBarCenter) {
        self.model = model
        self.placement = placement
        // 倒计时文本每秒变宽、hint 出现/消失——任何模型变化后重排，保持"宽度即内容"。
        modelObserver = model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.relayout() }
        }
        // 换屏 / 改分辨率：刘海几何会变，跟着重排。
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.relayout() }
        }
    }

    func apply(_ level: IslandController.Level) {
        self.level = level
        switch level {
        case .hidden:
            panel?.orderOut(nil)
        case .compact, .expanded:
            ensurePanel()
            switch placement {
            case .menuBarCenter:
                // 空闲点击穿透：圆点不需要手势，让出下方的菜单栏图标。
                panel?.ignoresMouseEvents = (level != .expanded)
            case .besideNotch:
                // 刘海旁是死区，圆点保持可点击（菜单入口兜底）。
                panel?.ignoresMouseEvents = false
            }
            relayout()
            panel?.orderFrontRegardless()
        }
    }

    // MARK: - private

    private func ensurePanel() {
        guard panel == nil else { return }
        let hosting = NSHostingView(rootView: MenuBarPillRoot(model: model))
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.hasShadow = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.contentView = hosting
        self.hosting = hosting
        self.panel = panel
    }

    /// 内容多高占多宽就开多大窗：比条带矮时垂直居中嵌入，
    /// 高出（展开 / hint）时顶边贴屏幕顶、向下垂出。
    private func relayout() {
        guard level != .hidden, let panel, let hosting, let screen = NSScreen.main else { return }
        let size = hosting.fittingSize
        guard size.width > 0, size.height > 0 else { return }

        let stripHeight: CGFloat
        let x: CGFloat
        switch placement {
        case .menuBarCenter:
            stripHeight = screen.frame.maxY - screen.visibleFrame.maxY
            x = (screen.frame.midX - size.width / 2).rounded()
        case .besideNotch:
            // 贴硬件刘海左缘：左缘 = minX + auxiliaryTopLeftArea.width；无刘海时退化为居中。
            stripHeight = max(screen.safeAreaInsets.top, screen.frame.maxY - screen.visibleFrame.maxY)
            if let leftArea = screen.auxiliaryTopLeftArea {
                x = (screen.frame.minX + leftArea.width - size.width - 6).rounded()
            } else {
                x = (screen.frame.midX - size.width / 2).rounded()
            }
        }

        let topInset = size.height >= stripHeight ? 0 : (stripHeight - size.height) / 2
        let frame = NSRect(
            x: x,
            y: screen.frame.maxY - topInset - size.height,
            width: size.width,
            height: size.height
        )
        panel.setFrame(frame, display: true)
    }
}

/// pill 后端的根视图：休眠 = 呼吸点；其余形态 = 黑色胶囊里的表单内容；hint 内嵌在布局里。
struct MenuBarPillRoot: View {
    @ObservedObject var model: IslandViewModel

    var body: some View {
        VStack(spacing: 3) {
            main
            if let hint = model.hint {
                HintBubble(text: hint)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.hint)
        .fixedSize()
    }

    @ViewBuilder
    private var main: some View {
        if case .idle = model.form {
            IslandCompactDot(model: model)
                .padding(.horizontal, 4)
                .padding(.vertical, 3)
        } else {
            IslandFormContent(model: model)
                .background(.black.opacity(0.88), in: Capsule())
        }
    }
}
