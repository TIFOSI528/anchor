import AppKit
import SwiftUI

/// 自管 NSWindow 承载 SwiftUI `SettingsView`。
///
/// Anchor 是 LSUIElement（无 Dock 图标），SwiftUI 标准 Settings 场景不便从
/// NSStatusItem 菜单程序化打开，所以自建窗口。
@MainActor
final class SettingsWindowController: NSWindowController {

    convenience init(coordinator: AppCoordinator) {
        let hosting = NSHostingController(
            rootView: SettingsView(library: coordinator.presetLibrary, coordinator: coordinator)
        )
        let window = NSWindow(contentViewController: hosting)
        window.title = "Anchor 设置"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 520, height: 440))
        window.isReleasedWhenClosed = false
        window.center()
        self.init(window: window)
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
