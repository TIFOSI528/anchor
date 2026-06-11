import AppKit

/// 三个手势的键盘等效（spec §七）：⌥⌘A = 拉回、⌥⌘B = 摸鱼、⌥⌘P = 暂停。
///
/// 本地监听始终可用；全局监听需要辅助功能权限——没授权就静默退化
/// （菜单栏里的等效菜单项仍然可用）。
@MainActor
final class HotkeyMonitor {

    var onSnapBack: () -> Void = {}
    var onSlack: () -> Void = {}
    var onPause: () -> Void = {}
    var onLockToggle: () -> Void = {}

    private var localMonitor: Any?
    private var globalMonitor: Any?

    func start() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.handle(event) == true { return nil }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            _ = self?.handle(event)
        }
    }

    func stop() {
        if let monitor = localMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = globalMonitor { NSEvent.removeMonitor(monitor) }
        localMonitor = nil
        globalMonitor = nil
    }

    private func handle(_ event: NSEvent) -> Bool {
        let required: NSEvent.ModifierFlags = [.option, .command]
        guard event.modifierFlags.intersection([.option, .command, .control, .shift]) == required,
              let key = event.charactersIgnoringModifiers?.lowercased() else {
            return false
        }
        switch key {
        case "a": onSnapBack(); return true
        case "b": onSlack(); return true
        case "p": onPause(); return true
        case "l": onLockToggle(); return true
        default: return false
        }
    }
}
