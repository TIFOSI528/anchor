import Foundation

/// 把 `AnchorState` 翻译成菜单栏的一行中文状态文字。
///
/// 纯函数、UI 无关，所以能在 AnchorCoreTests 里直接断言（见 CONTRIBUTING "可命令行测试"）。
public enum StatusLabel {

    /// 例：`.green` → "绿区"，`.drifting(30)` → "漂移 0:30"，`.slacking(120)` → "摸鱼 2:00"。
    public static func text(for state: AnchorState) -> String {
        switch state {
        case .green:
            return "绿区"
        case let .drifting(elapsed, _):
            return "漂移 " + clock(elapsed)
        case .red:
            return "红区"
        case let .slacking(remaining):
            return "摸鱼 " + clock(remaining)
        case .paused:
            return "已暂停"
        case .offline:
            return "待命"
        }
    }

    /// 把秒数格式化成 `m:ss`（负数按 0 处理）。
    private static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
