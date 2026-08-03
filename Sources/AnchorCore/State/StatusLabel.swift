import Foundation

/// 把 `AnchorState` 翻译成菜单栏的一行中文状态文字。
///
/// 文案全部走 `L()` 查表，实际语言跟随系统（上面那句"中文"是历史说法）。
/// 带时钟的两个状态整句进表（`"漂移 %1$@"`），不再 `"漂移 " + clock`——
/// 时长在句子里的位置不是每种语言都在后面。
///
/// 纯函数、UI 无关，所以能在 AnchorCoreTests 里直接断言（见 CONTRIBUTING "可命令行测试"）。
public enum StatusLabel {

    /// 例：`.green` → "绿区"，`.drifting(30)` → "漂移 0:30"，`.slacking(120)` → "摸鱼 2:00"。
    public static func text(for state: AnchorState) -> String {
        switch state {
        case .green:
            return L("status.green")
        case let .drifting(elapsed, _):
            return L("status.drifting", clock(elapsed))
        case .red:
            return L("status.red")
        case let .slacking(remaining):
            return L("status.slacking", clock(remaining))
        case .paused:
            return L("status.paused")
        case .offline:
            return L("status.offline")
        }
    }

    /// 把秒数格式化成 `m:ss`（负数按 0 处理）。
    ///
    /// 不再是 `private`：`text(for:)` 在单元测试里只会拿到 key（`L()` 查不到表就回落到 key，
    /// 参数会被 `String(format:)` 丢掉），时钟格式只能在这一层直接断言。
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
