import SwiftUI
import AnchorCore

/// 设置里那一行"这个功能到底能不能用"。
///
/// 这一小块 UI 的存在理由：依赖辅助功能权限的两个功能（全局快捷键、滚动锁）
/// 此前在没授权时**完全静默**——开关是开着的，按下快捷键没反应，界面上没有任何解释。
/// 与其反复弹系统弹窗骚扰用户，不如把真实状态和一个明确入口摆在这里。
struct PermissionStatusRow: View {
    let explanation: String

    @ObservedObject private var permissions = PermissionCenter.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundStyle(tint)
                Text(statusText)
                    .font(.callout)
                Spacer()
                if permissions.inputMonitoring != .granted {
                    Button(L("settings.permission.grant")) {
                        permissions.requestInputMonitoring()
                    }
                    .controlSize(.small)
                    Button(L("settings.permission.open_settings")) {
                        permissions.openSystemSettings()
                    }
                    .controlSize(.small)
                }
            }
            if permissions.inputMonitoring != .granted {
                Text(explanation)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        // 每次设置窗口出现时重新读一遍：用户可能刚在系统设置里改过。
        .onAppear { permissions.refresh() }
    }

    private var icon: String {
        switch permissions.inputMonitoring {
        case .granted: return "checkmark.circle.fill"
        case .denied: return "exclamationmark.triangle.fill"
        case .notDetermined: return "questionmark.circle"
        }
    }

    private var tint: Color {
        switch permissions.inputMonitoring {
        case .granted: return .green
        case .denied: return .orange
        case .notDetermined: return .secondary
        }
    }

    private var statusText: String {
        switch permissions.inputMonitoring {
        case .granted: return L("permission.status.granted")
        case .denied: return L("permission.status.denied")
        case .notDetermined: return L("permission.status.not_determined")
        }
    }
}
