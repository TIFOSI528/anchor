import SwiftUI
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
            .accessibilityHint("单击拉回（⌥⌘A）· 长按 3 秒合法摸鱼（⌥⌘B）· 上划暂停（⌥⌘P）")
    }

    @ViewBuilder
    private var content: some View {
        switch model.form {
        case .idle:
            BreathingDot()

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
            .accessibilityLabel(model.locked ? "Anchor：已锁定" : "Anchor")
            .accessibilityHint("点击打开 Anchor 菜单")
    }

    private var dotColor: Color {
        switch model.form {
        // 锁定中的休眠点用蓝色区分（"只看这个"会话进行中）。
        case .idle: return model.locked ? Color(hex: 0x3B82F6) : Color(hex: 0x22C55E)
        case .drift, .deepening, .slacking: return Color(hex: 0xF59E0B)
        case .red: return Color(hex: 0xDC2626)
        }
    }
}

/// 2 秒周期呼吸动画的小圆点（形态 0）。
struct BreathingDot: View {
    var color: Color = Color(hex: 0x22C55E)
    @State private var bright = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .opacity(bright ? 1.0 : 0.35)
            .onAppear {
                withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
                    bright = true
                }
            }
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
