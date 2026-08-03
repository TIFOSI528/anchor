import AppKit
import AnchorCore

/// 上划暂停时的强制理由输入（dynamic-island-spec §四 手势 3）：必须 ≥ 10 个字符。
@MainActor
enum PauseReasonPrompt {

    static let minimumLength = 10

    /// 返回合法理由；用户取消返回 nil。长度不足时带提示重新询问。
    static func ask() -> String? {
        var message = L("prompt.pause_reason.message", Int64(minimumLength))
        while true {
            let alert = NSAlert()
            alert.messageText = L("prompt.pause_reason.title")
            alert.informativeText = message
            alert.addButton(withTitle: L("prompt.pause_reason.confirm"))
            alert.addButton(withTitle: L("prompt.pause_reason.cancel"))

            let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
            field.placeholderString = L("prompt.pause_reason.placeholder")
            alert.accessoryView = field
            alert.window.initialFirstResponder = field

            NSApp.activate(ignoringOtherApps: true)
            guard alert.runModal() == .alertFirstButtonReturn else { return nil }

            let reason = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if reason.count >= minimumLength {
                return reason
            }
            message = L("prompt.pause_reason.too_short", Int64(reason.count), Int64(minimumLength))
        }
    }
}
