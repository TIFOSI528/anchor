import AppKit
import ApplicationServices
import AnchorCore

/// 权限状态的单一信息源。
///
/// **修的是什么**：此前全局快捷键在没有权限时"静默降级"——用户按 ⌃⌥⌘A 什么也不发生，
/// 没有提示、没有状态、没有去授权的入口；「深度漂移时锁定滚动」开关也写着"需辅助功能权限"
/// 却从不请求也从不校验，打开后永远无效。沉默不是优雅降级，是让用户以为功能坏了。
@MainActor
final class PermissionCenter: ObservableObject {

    static let shared = PermissionCenter()

    enum Status: Equatable {
        case granted
        case denied
        /// 还没问过（首次启动、或用户从未在系统弹窗里做选择）。
        case notDetermined
    }

    /// 全局快捷键与滚动锁都依赖"能否观察系统输入事件"。
    /// macOS 上这归 辅助功能 / 输入监控 管，`AXIsProcessTrusted()` 是可靠的判据。
    @Published private(set) var inputMonitoring: Status = .notDetermined

    private var pollTimer: Timer?

    private init() {
        refresh()
    }

    func refresh() {
        let trusted = AXIsProcessTrusted()
        if trusted {
            inputMonitoring = .granted
        } else if UserDefaults.standard.bool(forKey: SettingsKey.didRequestInputMonitoring) {
            // 问过了还是不 trusted → 用户拒绝了（或还没在系统设置里勾上）。
            inputMonitoring = .denied
        } else {
            inputMonitoring = .notDetermined
        }
    }

    /// 触发系统授权弹窗。只在用户主动点「授权」时调用——
    /// 绝不在启动时偷偷弹（装完几秒后冒出"某 app 想接收你的按键"是不可挽回的信任事件）。
    func requestInputMonitoring() {
        UserDefaults.standard.set(true, forKey: SettingsKey.didRequestInputMonitoring)
        // 直接用字面量：`kAXTrustedCheckOptionPrompt` 是可变全局，Swift 6 严格并发下
        // 引用它会报"涉及共享可变状态"。这个 key 的取值是稳定的公开约定。
        let promptKey = "AXTrustedCheckOptionPrompt" as CFString
        _ = AXIsProcessTrustedWithOptions([promptKey: kCFBooleanTrue] as CFDictionary)
        // 系统弹窗是异步的，且用户可能直接去设置里勾选——轮询一小段时间把状态追上来。
        startPolling()
    }

    func openSystemSettings() {
        // 直达 隐私与安全性 → 辅助功能。
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        if let url { NSWorkspace.shared.open(url) }
        startPolling()
    }

    /// 授权变化没有通知可订阅，只能轮询。限时 60 秒，避免常驻定时器违背"绿区零后台工作"。
    private func startPolling() {
        pollTimer?.invalidate()
        let deadline = Date().addingTimeInterval(60)
        // 不把闭包参数 `timer` 带进 MainActor 闭包——Swift 6 会判定为跨隔离域发送非 Sendable
        // 值（"sending 'timer' risks causing data races"）。改用已存的 `pollTimer` 自我了结。
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.refresh()
                if self.inputMonitoring == .granted || Date() > deadline {
                    self.pollTimer?.invalidate()
                    self.pollTimer = nil
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }
}

extension SettingsKey {
    /// 是否已经向系统请求过输入监控权限（用于区分"没问过"与"被拒绝"）。
    static let didRequestInputMonitoring = "anchor.didRequestInputMonitoring"
    /// 首启引导是否已完成。
    static let hasCompletedOnboarding = "anchor.hasCompletedOnboarding"
}
