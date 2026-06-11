import AppKit

/// 上划暂停时的强制理由输入（dynamic-island-spec §四 手势 3）：必须 ≥ 10 个字符。
@MainActor
enum PauseReasonPrompt {

    static let minimumLength = 10

    /// 返回合法理由；用户取消返回 nil。长度不足时带提示重新询问。
    static func ask() -> String? {
        var message = "暂停看护前，请写下原因（≥ \(minimumLength) 个字符）——它会进今晚的复盘："
        while true {
            let alert = NSAlert()
            alert.messageText = "暂停看护"
            alert.informativeText = message
            alert.addButton(withTitle: "暂停")
            alert.addButton(withTitle: "取消")

            let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
            field.placeholderString = "例如：要去开 1 小时的评审会"
            alert.accessoryView = field
            alert.window.initialFirstResponder = field

            NSApp.activate(ignoringOtherApps: true)
            guard alert.runModal() == .alertFirstButtonReturn else { return nil }

            let reason = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if reason.count >= minimumLength {
                return reason
            }
            message = "理由太短（\(reason.count)/\(minimumLength)），写具体一点。"
        }
    }
}
