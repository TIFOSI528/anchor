import AppKit
import SwiftUI
import AnchorCore

/// 复盘窗口宿主。数据由 coordinator 组装好后注入。
@MainActor
final class RecapWindowController: NSWindowController {

    convenience init(data: RecapData?) {
        let hosting = NSHostingController(rootView: RecapView(data: data))
        let window = NSWindow(contentViewController: hosting)
        window.title = "今日复盘"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        self.init(window: window)
    }

    func show(data: RecapData?) {
        if let hosting = window?.contentViewController as? NSHostingController<RecapView> {
            hosting.rootView = RecapView(data: data)
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
