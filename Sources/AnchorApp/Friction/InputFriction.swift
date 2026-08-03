import AppKit
import CoreGraphics

/// 可选的滚动锁（PR #16）：顶层 friction（heavy）时吞掉滚轮事件。
///
/// - **默认 OFF**，只有用户在 Settings 显式打开才介入
/// - 需要辅助功能权限（`AXIsProcessTrusted`）；没有权限就静默不生效
/// - 只拦 `scrollWheel`，绝不碰键盘/点击——可逆、低风险
@MainActor
final class InputFriction {

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    var isEnabled: () -> Bool = { false }

    func update(level: Double) {
        let shouldLock = isEnabled() && level >= 0.8 && AXIsProcessTrusted()
        if shouldLock {
            installTapIfNeeded()
        } else {
            removeTap()
        }
    }

    private func installTapIfNeeded() {
        guard tap == nil else { return }
        let mask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, _, event, _ in
                // **放过投给 Anchor 自己的滚动**。
                // 此前这里无条件返回 nil，等于全会话吞掉滚轮——包括 Anchor 自己的
                // 设置窗口和复盘窗口（两者都是 ScrollView）。于是"深度漂移时锁定滚动"
                // 一旦触发，用户就滚不到那个用来关掉它的开关，被自己的设置困住。
                let targetPID = event.getIntegerValueField(.eventTargetUnixProcessID)
                if targetPID == Int64(ProcessInfo.processInfo.processIdentifier) {
                    return Unmanaged.passUnretained(event)
                }
                return nil // 其余照旧吞掉
            },
            userInfo: nil
        ) else { return }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func removeTap() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        self.tap = nil
        runLoopSource = nil
    }
}
