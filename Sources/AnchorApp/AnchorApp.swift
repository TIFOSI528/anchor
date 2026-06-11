import SwiftUI
import AnchorCore
import AnchorDaemon

@main
struct AnchorApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Anchor 是一个 menu-bar / overlay app，无主窗口。
        // 灵动岛和 Settings 都由 AppDelegate 管理。
        Settings {
            EmptyView()
        }
    }
}
