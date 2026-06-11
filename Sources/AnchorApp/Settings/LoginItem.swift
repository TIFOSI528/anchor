import Foundation
import ServiceManagement

/// 开机自启动开关。基于 `SMAppService`（macOS 13+）。
///
/// 在未签名的 dev 运行下注册可能失败——这里静默吞掉，不影响其它功能。
enum LoginItem {
    static func set(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("[Anchor] login item toggle failed: \(error.localizedDescription)")
        }
    }

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }
}
