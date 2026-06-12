import AppKit
import SwiftUI
import AnchorCore
import DynamicNotchKit

/// 灵动岛控制器：把 `AnchorState` 映射成形态/展开级别，并在形态升级时播触感。
///
/// `style: .auto` 由 DynamicNotchKit 负责 notch 探测与非刘海 Mac 的 top-center 浮窗
/// fallback（PR #9）。v1 只在主屏显示；多屏每屏一岛排到 v1.1。
@MainActor
final class IslandController {

    let model = IslandViewModel()

    enum Level: Int { case hidden, compact, expanded }

    private var notch: (any DynamicNotchControllable)?
    private var pill: MenuBarPillRenderer?
    /// 真刘海屏的绿区侧点：不画黑壳，零覆盖贴在硬件刘海左侧（下沿绝对对齐）。
    private var sideDot: MenuBarPillRenderer?
    private var level: Level = .hidden
    private var lastFormKind = 0

    var hapticsEnabled: () -> Bool = { true }

    init() {
        let model = self.model
        let raw = UserDefaults.standard.string(forKey: SettingsKey.islandPosition) ?? ""
        let position = IslandPosition(rawValue: raw) ?? .auto
        let hasNotch = Self.screenHasNotch

        // 「灵动岛位置」在 init 时读取，更改后重启生效（窗口此时创建）。
        // hover 行为一律关闭：展开/收起完全由状态机驱动，keepVisible 会让
        // hide() 在鼠标悬停时每 0.1s 重试——拉回后壳收不掉、出现双绿点 + 卡顿。
        if hasNotch, position == .auto || position == .notch {
            // 真刘海：顶角半径 0 → 展开面板宽度与硬件刘海严格相等（不外扩 2×15pt）；
            // compact 由零覆盖侧点接管，黑壳里不放任何 compact 内容。
            notch = DynamicNotch(
                hoverBehavior: [],
                style: .notch(topCornerRadius: 0, bottomCornerRadius: 14),
                expanded: { IslandExpandedView(model: model) }
            )
            sideDot = MenuBarPillRenderer(model: model, placement: .besideNotch)
        } else {
            switch position {
            case .auto, .menuBar:
                pill = MenuBarPillRenderer(model: model)
            case .notch: // 无刘海屏强制人造刘海
                notch = DynamicNotch(
                    hoverBehavior: [],
                    style: .notch,
                    expanded: { IslandExpandedView(model: model) },
                    compactLeading: { IslandCompactDot(model: model) }
                )
            case .topCenter:
                notch = DynamicNotch(
                    hoverBehavior: [],
                    style: .floating,
                    expanded: { IslandExpandedView(model: model) },
                    compactLeading: { IslandCompactDot(model: model) }
                )
            }
        }
    }

    private static var screenHasNotch: Bool {
        (NSScreen.main?.safeAreaInsets.top ?? 0) > 0
    }

    /// 真刘海屏优先（外接屏环境下岛跟着刘海走，与参考实现一致）。
    private static var targetScreen: NSScreen {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    /// 由 coordinator 在每次状态变化 / tick 时调用。
    func render(state: AnchorState, redElapsed: Int, driftThreshold: Int, snapBackName: String?) {
        switch state {
        case .green:
            model.form = .idle
            transition(to: .compact)

        case let .drifting(elapsed, _):
            let seconds = Int(elapsed)
            if seconds < 60 {
                model.form = .drift(elapsed: seconds, threshold: driftThreshold)
            } else if seconds < 180 {
                model.form = .deepening(elapsed: seconds, target: snapBackName)
            } else {
                model.form = .red(elapsed: seconds)
            }
            transition(to: .expanded)

        case .red:
            model.form = .red(elapsed: redElapsed)
            transition(to: .expanded)

        case let .slacking(remaining):
            model.form = .slacking(remaining: Int(remaining), total: 300)
            transition(to: .expanded)

        case .paused, .offline:
            model.form = .idle
            transition(to: .hidden)
        }
        playUpgradeHapticIfNeeded()
    }

    func flashHint(_ text: String) {
        model.flashHint(text)
        // pill / 侧点：hint 内嵌在布局里，模型监听自动重排，无需展开动作。
        guard pill == nil, sideDot == nil else { return }
        if level == .compact, let notch {
            // 绿区时短暂展开展示 hint，随后缩回。
            Task {
                await notch.expand(on: Self.targetScreen)
                try? await Task.sleep(for: .seconds(1.8))
                if self.level == .compact { await notch.compact(on: Self.targetScreen) }
            }
        }
    }

    // MARK: - private

    private func transition(to target: Level) {
        if let pill {
            level = target
            pill.apply(target)
            return
        }
        guard target != level, let notch else { return }
        level = target

        // 真刘海混合模式：compact = 侧点（零覆盖），expanded = 从刘海长出的岛。
        if let sideDot {
            sideDot.apply(target == .compact ? .compact : .hidden)
            Task {
                switch target {
                case .expanded: await notch.expand(on: Self.targetScreen)
                case .compact, .hidden: await notch.hide()
                }
            }
            return
        }

        Task {
            switch target {
            case .hidden: await notch.hide()
            case .compact: await notch.compact(on: Self.targetScreen)
            case .expanded: await notch.expand(on: Self.targetScreen)
            }
        }
    }

    /// 形态 1→2 `.alignment`、2→3 `.levelChange`（spec §五 触感表）。
    private func playUpgradeHapticIfNeeded() {
        let kind: Int
        switch model.form {
        case .idle: kind = 0
        case .drift: kind = 1
        case .deepening: kind = 2
        case .red: kind = 3
        case .slacking: kind = 1
        }
        defer { lastFormKind = kind }
        guard hapticsEnabled(), kind > lastFormKind else { return }
        if lastFormKind == 1, kind == 2 {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        } else if lastFormKind == 2, kind == 3 {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .default)
        }
    }
}
