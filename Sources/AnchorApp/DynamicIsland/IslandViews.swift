import SwiftUI
import AppKit
import AnchorCore

/// notch 后端的展开态：内容 + 悬挂在下方的 hint 气泡。
struct IslandExpandedView: View {
    @ObservedObject var model: IslandViewModel

    var body: some View {
        IslandFormContent(model: model)
            .overlay(alignment: .bottom) {
                if let hint = model.hint {
                    HintBubble(text: hint)
                        .offset(y: 26)
                        .transition(.opacity)
                }
            }
    }
}

/// hint 气泡（notch 下方悬挂 / pill 布局内嵌共用）。
struct HintBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.black.opacity(0.85), in: Capsule())
            .foregroundStyle(.white)
    }
}

/// 四种非休眠形态 + 三手势（不含 hint，由宿主决定 hint 怎么放）。
/// 所有过渡 200ms ease-out（spec §三/§五）。
struct IslandFormContent: View {
    @ObservedObject var model: IslandViewModel

    var body: some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .animation(.easeOut(duration: 0.2), value: model.form)
            .contentShape(Rectangle())
            .onTapGesture { model.onTap() }
            .onLongPressGesture(minimumDuration: 3) {
                model.onLongPress()
            } onPressingChanged: { pressing in
                model.pressing = pressing
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 30).onEnded { value in
                    if value.translation.height < -30 { model.onSwipeUp() }
                }
            )
            .overlay(RightClickCatcher { model.onSecondaryClick() }) // 右键=完整菜单
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
            .accessibilityHint(L("island.a11y.gestures_hint"))
    }

    @ViewBuilder
    private var content: some View {
        switch model.form {
        case .idle:
            // 展开壳里不放休眠点：拉回后收起动画期间会闪出"壳内绿点"（侧点已在刘海旁）。
            Color.clear.frame(width: 2, height: 2)

        case let .drift(elapsed, threshold):
            // 这一形态此前是唯一**没有背景**却写死 .white 的：在「顶部居中浮窗」位置下，
            // DynamicNotchKit 用 .popover 材质（浅色模式下近白），于是倒计时白字白底、完全看不见。
            // 补上与其它三态一致的胶囊底。
            HStack(spacing: 8) {
                CountdownRing(
                    progress: threshold > 0 ? min(1, Double(elapsed) / Double(threshold)) : 0,
                    color: elapsed >= 30 ? Color(hex: 0xFBBF24) : Color(hex: 0xF59E0B)
                )
                .frame(width: 14, height: 14)
                Text(IslandViewModel.clock(elapsed))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(.black.opacity(0.85), in: Capsule())

        case let .deepening(elapsed, target):
            HStack(spacing: 6) {
                Text(IslandViewModel.clock(elapsed))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                Text(L("island.snap_back_to", target ?? L("island.snap_back_fallback")))
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(Color(hex: 0xD97706), in: Capsule())

        case let .red(elapsed):
            Text(L("island.red_away", Self.duration(elapsed)))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Color(hex: 0xDC2626), in: Capsule())

        case let .slacking(remaining, total):
            HStack(spacing: 8) {
                CountdownRing(
                    progress: total > 0 ? Double(remaining) / Double(total) : 0,
                    color: .white
                )
                .frame(width: 14, height: 14)
                Text(IslandViewModel.clock(remaining))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(Color(hex: 0xF59E0B), in: Capsule())
        }
    }

    private var accessibilityText: String {
        switch model.form {
        case .idle: return L("island.a11y.green")
        case let .drift(elapsed, _): return L("island.a11y.drifting", Self.duration(elapsed))
        case let .deepening(elapsed, target):
            return L("island.a11y.deepening", Self.duration(elapsed), target ?? L("island.snap_back_fallback"))
        case let .red(elapsed): return L("island.a11y.red", Self.duration(elapsed))
        case let .slacking(remaining, _): return L("island.a11y.slacking", Self.duration(remaining))
        }
    }

    /// 时长文案：< 60s 用"X 秒"，之后用 m:ss——红区文字不会长成"已离开 600 秒"。
    /// m:ss 是纯数字格式，各语言通用，不进译文表。
    static func duration(_ seconds: Int) -> String {
        seconds < 60
            ? L("island.duration_seconds", Int64(max(0, seconds)))
            : IslandViewModel.clock(seconds)
    }
}

/// 紧凑态（notch 左侧）：休眠呼吸绿点；漂移中变橙提醒。
struct IslandCompactDot: View {
    @ObservedObject var model: IslandViewModel

    var body: some View {
        ZStack {
            BreathingDot(color: dotColor)
            // 非颜色线索：整个产品语义此前只靠这颗 8pt 圆点的**色相**表达
            // （绿=专注 / 琥珀=漂移 / 红=红区 / 蓝=锁定 / 灰=暂停）。
            // 对红绿色盲（约 8% 男性）来说 8px 的绿与红是最经典的混淆对，
            // 等于整个稳态无法辨认。这里叠一个极小的符号做冗余编码。
            if let glyph = stateGlyph {
                Image(systemName: glyph)
                    .font(.system(size: 6, weight: .black))
                    .foregroundStyle(.black.opacity(0.75))
                    .allowsHitTesting(false)
            }
        }
        .frame(width: 18, height: 14) // 命中区比 8pt 圆点大一圈
        .contentShape(Rectangle())
        .onTapGesture { model.onDotTap() }
        .overlay(RightClickCatcher { model.onSecondaryClick() })
        .accessibilityLabel(accessibilityText)
        .accessibilityHint(L("island.a11y.dot_hint"))
    }

    /// 叠在圆点上的形状线索。绿区（一切正常）保持纯圆点——好工具在绿区应该隐形。
    private var stateGlyph: String? {
        if model.paused { return "pause" }
        switch model.form {
        case .idle: return model.locked ? "lock" : nil
        case .drift, .deepening: return "exclamationmark"
        case .slacking: return "cup.and.saucer"
        case .red: return "xmark"
        }
    }

    private var accessibilityText: String {
        if model.paused { return L("island.a11y.paused") }
        if model.locked { return L("island.a11y.locked") }
        return "Anchor" // 品名，不翻译
    }

    private var dotColor: Color {
        // 暂停 = 灰点（保留入口）；锁定 = 蓝点；正常休眠 = 绿点。
        if model.paused { return Color(hex: 0x94A3B8) }
        switch model.form {
        case .idle: return model.locked ? Color(hex: 0x3B82F6) : Color(hex: 0x22C55E)
        case .drift, .deepening, .slacking: return Color(hex: 0xF59E0B)
        case .red: return Color(hex: 0xDC2626)
        }
    }
}

/// 2 秒周期呼吸动画的小圆点（形态 0）。
///
/// 用 CALayer 的 `CABasicAnimation` 而非 SwiftUI `repeatForever`：动画交给 WindowServer
/// 渲染线程插值，app 主线程稳态 ~0% CPU——满足"绿区不触发任何 UI 重绘"的能耗不变量
/// （SwiftUI repeatForever 会持续 churn 渲染循环，实测空闲 ~2.5% CPU）。
struct BreathingDot: NSViewRepresentable {
    var color: Color = Color(hex: 0x22C55E)

    func makeNSView(context: Context) -> BreathingDotView {
        BreathingDotView()
    }

    func updateNSView(_ view: BreathingDotView, context: Context) {
        view.dotColor = NSColor(color)
    }
}

final class BreathingDotView: NSView {
    private let dot = CALayer()

    var dotColor: NSColor = .systemGreen {
        didSet {
            // 改色不重启动画：合成器动画不受影响。
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            dot.backgroundColor = dotColor.cgColor
            CATransaction.commit()
        }
    }

    override var intrinsicContentSize: NSSize { NSSize(width: 8, height: 8) }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        dot.bounds = CGRect(x: 0, y: 0, width: 8, height: 8)
        dot.cornerRadius = 4
        dot.backgroundColor = dotColor.cgColor
        layer?.addSublayer(dot)

        applyBreathingIfAllowed()

        // 系统「减少动态效果」是可以随时改的，跟着走。
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(reduceMotionChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )
    }

    @objc private func reduceMotionChanged() {
        applyBreathingIfAllowed()
    }

    /// 这颗点是**常驻**元素，无限呼吸对前庭功能障碍 / 偏头痛用户是持续触发源，
    /// 而此前它在 `init` 里无条件安装，没有任何代码路径能停下来。
    /// 现在尊重系统「辅助功能 → 显示 → 减少动态效果」。
    private func applyBreathingIfAllowed() {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            dot.removeAnimation(forKey: "breath")
            dot.opacity = 1
            return
        }
        guard dot.animation(forKey: "breath") == nil else { return }
        let breath = CABasicAnimation(keyPath: "opacity")
        breath.fromValue = 0.35
        breath.toValue = 1.0
        breath.duration = 1.0
        breath.autoreverses = true
        breath.repeatCount = .infinity
        breath.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        breath.isRemovedOnCompletion = false
        dot.add(breath, forKey: "breath")
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        dot.position = CGPoint(x: bounds.midX, y: bounds.midY)
    }
}

/// 倒计时圆环。
struct CountdownRing: View {
    let progress: Double
    let color: Color

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.25), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: max(0, min(1, progress)))
                .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .animation(.linear(duration: 1), value: progress)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// 透明覆盖层：**只捕获右键**，左键/长按/拖拽全部穿透给底下的 SwiftUI 手势。
/// 用 hitTest 按当前事件类型决定认不认领——右键才返回自己，否则返回 nil 放行。
struct RightClickCatcher: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> RightClickView {
        let view = RightClickView()
        view.onRightClick = action
        return view
    }

    func updateNSView(_ view: RightClickView, context: Context) {
        view.onRightClick = action
    }
}

final class RightClickView: NSView {
    var onRightClick: () -> Void = {}

    override func hitTest(_ point: NSPoint) -> NSView? {
        switch NSApp.currentEvent?.type {
        case .rightMouseDown, .rightMouseUp:
            return self          // 认领右键
        default:
            return nil           // 其余事件穿透到下层 SwiftUI
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick()
    }
}
