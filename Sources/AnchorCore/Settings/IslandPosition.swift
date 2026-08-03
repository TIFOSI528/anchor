import Foundation

/// 灵动岛显示位置。`auto` 时：有 notch 的 Mac 用 notch，否则菜单栏嵌入。
public enum IslandPosition: String, CaseIterable, Identifiable, Sendable {
    case auto
    /// 自研后端：宽度=内容的胶囊嵌在菜单栏中段，空闲点击穿透（无刘海机型推荐）。
    case menuBar
    case notch
    case topCenter

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .auto: return L("island.position.auto")
        case .menuBar: return L("island.position.menu_bar")
        case .notch: return L("island.position.notch")
        case .topCenter: return L("island.position.top_center")
        }
    }
}
