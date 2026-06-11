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

    private var notch: DynamicNotch<IslandExpandedView, IslandCompactDot, EmptyView>?
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
        let style: DynamicNotchStyle?
        switch position {
        case .auto: style = hasNotch ? .auto : nil // 无刘海 → 自研菜单栏嵌入
        case .menuBar: style = nil
        case .notch: style = .notch
        case .topCenter: style = .floating
        }

        if let style {
            notch = DynamicNotch(
                hoverBehavior: [.keepVisible],
                style: style,
                expanded: { IslandExpandedView(model: model) },
                compactLeading: { IslandCompactDot(model: model) }
            )
            // 真刘海 + 非浮窗：compact 用零覆盖侧点替代 DynamicNotchKit 的黑壳
            // （黑壳底角 14pt 比硬件刘海肥、hover 还会多出 1–2pt，见设计稿修订）。
            if hasNotch, position != .topCenter {
                sideDot = MenuBarPillRenderer(model: model, placement: .besideNotch)
            }
        } else {
            pill = MenuBarPillRenderer(model: model)
        }
    }

    private static var screenHasNotch: Bool {
        (NSScreen.main?.safeAreaInsets.top ?? 0) > 0
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
                await notch.expand()
                try? await Task.sleep(for: .seconds(1.8))
                if self.level == .compact { await notch.compact() }
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
                case .expanded: await notch.expand()
                case .compact, .hidden: await notch.hide()
                }
            }
            return
        }

        Task {
            switch target {
            case .hidden: await notch.hide()
            case .compact: await notch.compact()
            case .expanded: await notch.expand()
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
