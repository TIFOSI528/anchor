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
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
            .accessibilityHint("单击拉回（⌃⌥⌘A）· 长按 3 秒合法摸鱼（⌃⌥⌘B）· 上划暂停（⌃⌥⌘P）")
    }

    @ViewBuilder
    private var content: some View {
        switch model.form {
        case .idle:
            // 展开壳里不放休眠点：拉回后收起动画期间会闪出"壳内绿点"（侧点已在刘海旁）。
            Color.clear.frame(width: 2, height: 2)

        case let .drift(elapsed, threshold):
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

        case let .deepening(elapsed, target):
            HStack(spacing: 6) {
                Text(IslandViewModel.clock(elapsed))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                Text("↩ 回到 \(target ?? "绿区")")
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(Color(hex: 0xD97706), in: Capsule())

        case let .red(elapsed):
            Text("立即拉回 · 已离开 \(Self.duration(elapsed))")
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
        case .idle: return "Anchor：绿区"
        case let .drift(elapsed, _): return "漂移中，已 \(Self.duration(elapsed))"
        case let .deepening(elapsed, target): return "漂移加深，已 \(Self.duration(elapsed))，可拉回 \(target ?? "绿区")"
        case let .red(elapsed): return "红区，已离开 \(Self.duration(elapsed))"
        case let .slacking(remaining, _): return "合法摸鱼，剩余 \(Self.duration(remaining))"
        }
    }

    /// 时长文案：< 60s 用"X 秒"，之后用 m:ss——红区文字不会长成"已离开 600 秒"。
    static func duration(_ seconds: Int) -> String {
        seconds < 60 ? "\(max(0, seconds)) 秒" : IslandViewModel.clock(seconds)
    }
}

/// 紧凑态（notch 左侧）：休眠呼吸绿点；漂移中变橙提醒。
struct IslandCompactDot: View {
    @ObservedObject var model: IslandViewModel

    var body: some View {
        BreathingDot(color: dotColor)
            .frame(width: 18, height: 14) // 命中区比 8pt 圆点大一圈
            .contentShape(Rectangle())
            .onTapGesture { model.onDotTap() }
            .accessibilityLabel(accessibilityText)
            .accessibilityHint("点击打开 Anchor 菜单")
    }

    private var accessibilityText: String {
        if model.paused { return "Anchor：已暂停，点击恢复" }
        if model.locked { return "Anchor：已锁定" }
        return "Anchor"
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
