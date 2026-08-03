import AppKit
import SwiftUI
import AnchorCore

/// 承载首启引导的窗口。
///
/// `LSUIElement` 的 app 没有 Dock 图标，所以必须 `activate(ignoringOtherApps:)`
/// 才能真的出现在用户眼前——这是唯一一处"抢焦点"是正确的场景：
/// 用户刚双击了 app，期待看到东西。
@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {

    private var window: NSWindow?
    private let library: PresetLibrary

    init(library: PresetLibrary) {
        self.library = library
        super.init()
    }

    /// 点标题栏红叉关掉也算看完——否则引导会在每次启动时重新弹出来，
    /// 而"关掉窗口"恰恰是用户表达"我不想看"最直接的方式。
    func windowWillClose(_ notification: Notification) {
        UserDefaults.standard.set(true, forKey: SettingsKey.hasCompletedOnboarding)
        window = nil
    }

    /// 是否还需要引导（首次启动，或用户从菜单里主动再看一次）。
    static var needsOnboarding: Bool {
        !UserDefaults.standard.bool(forKey: SettingsKey.hasCompletedOnboarding)
    }

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let controller = NSHostingController(
            rootView: OnboardingView(library: library) { [weak self] in
                UserDefaults.standard.set(true, forKey: SettingsKey.hasCompletedOnboarding)
                self?.close()
            }
        )
        let window = NSWindow(contentViewController: controller)
        window.title = L("onboarding.window_title")
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 直接关窗也算完成——不把用户困在引导里（引导本身也要有逃生通道）。
    private func close() {
        window?.close()
        window = nil
    }
}
