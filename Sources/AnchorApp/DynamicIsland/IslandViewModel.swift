import SwiftUI
import AnchorCore

/// 灵动岛的渲染模型。`IslandController` 写、SwiftUI 视图读。
@MainActor
final class IslandViewModel: ObservableObject {

    /// 五种视觉形态（dynamic-island-spec §三）。
    enum Form: Equatable {
        /// 形态 0：休眠绿点。
        case idle
        /// 形态 1：刚漂移（圆环 + 计时）。
        case drift(elapsed: Int, threshold: Int)
        /// 形态 2：漂移加深（橙色 + 拉回按钮）。
        case deepening(elapsed: Int, target: String?)
        /// 形态 3：红区 / 顶层 friction。
        case red(elapsed: Int)
        /// 形态 4：合法摸鱼倒计时。
        case slacking(remaining: Int, total: Int)
    }

    @Published var form: Form = .idle
    /// 0.5s 自动消失的轻提示（如"暂无可拉回的目标"）。
    @Published var hint: String?
    /// 长按进行中（视觉渐变橙 + "摸一会儿吧"）。
    @Published var pressing = false
    /// Focus Lock 激活中（休眠点变蓝，提示"只看这个"会话进行中）。
    @Published var locked = false
    /// 暂停看护中（休眠点变灰——保留入口，点击可恢复）。
    @Published var paused = false

    var onTap: () -> Void = {}
    var onLongPress: () -> Void = {}
    var onSwipeUp: () -> Void = {}
    /// 绿区休眠点被点击（刘海模式下作为菜单入口的兜底）。
    var onDotTap: () -> Void = {}
    /// 任何状态右键岛 → 弹完整 Anchor 菜单（不依赖菜单栏图标、不用快捷键）。
    var onSecondaryClick: () -> Void = {}

    private var hintTask: Task<Void, Never>?

    func flashHint(_ text: String, seconds: Double = 1.6) {
        hintTask?.cancel()
        hint = text
        hintTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.hint = nil
        }
    }

    static func clock(_ seconds: Int) -> String {
        String(format: "%d:%02d", max(0, seconds) / 60, max(0, seconds) % 60)
    }
}
