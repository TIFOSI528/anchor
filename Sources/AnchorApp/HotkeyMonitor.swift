import AppKit

/// 手势的键盘等效（spec §七）：⌃⌥⌘A 拉回、⌃⌥⌘B 摸鱼、⌃⌥⌘L 锁定、⌃⌥⌘P 暂停/恢复。
///
/// 用三修饰键组合降低与其它 app 的冲突概率（⌥⌘ 系列被 IDE/效率工具大量占用）。
/// 注意：macOS 全局监听只能"旁听"无法拦截——若仍与某 app 撞车，可在设置里整体关闭。
/// 本地监听始终可用；全局监听需要辅助功能权限——没授权就静默退化（菜单项仍可用）。
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

    /// 物理键位（ANSI virtual key code）。
    ///
    /// 此前用 `charactersIgnoringModifiers` 判定，那拿到的是**经键盘布局映射后**的字符：
    /// AZERTY 上 QWERTY 的 A 位于 Q 键处，Dvorak / Colemak 同理，
    /// 非拉丁布局（西里尔 / 希腊 / 阿拉伯）下含 `.control` 的组合更不保证有拉丁替换。
    /// 结果是文档写着 ⌃⌥⌘A，用户按下去却什么都不发生。按 keyCode 匹配则与布局无关。
    private enum Key: UInt16 {
        case a = 0
        case b = 11
        case l = 37
        case p = 35
    }

    private func handle(_ event: NSEvent) -> Bool {
        let required: NSEvent.ModifierFlags = [.control, .option, .command]
        guard event.modifierFlags.intersection([.option, .command, .control, .shift]) == required,
              let key = Key(rawValue: event.keyCode) else {
            return false
        }
        switch key {
        case .a: onSnapBack(); return true
        case .b: onSlack(); return true
        case .p: onPause(); return true
        case .l: onLockToggle(); return true
        }
    }
}
