import AppKit
import UniformTypeIdentifiers

/// bundleId → (系统应用图标, 显示名)。纯展示层：渲染时解析、NSCache 缓存，
/// 不进数据模型（设计稿见 docs/plans/2026-06-10-preset-icon-editor-design.md）。
@MainActor
enum AppIconProvider {

    private static let iconCache = NSCache<NSString, NSImage>()
    private static var nameCache: [String: String] = [:]

    static func icon(forBundleId bundleId: String) -> NSImage {
        if let cached = iconCache.object(forKey: bundleId as NSString) {
            return cached
        }
        let icon: NSImage
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            icon = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            // 本机未安装：通用应用图标兜底
            icon = NSWorkspace.shared.icon(for: .applicationBundle)
        }
        icon.size = NSSize(width: 16, height: 16)
        iconCache.setObject(icon, forKey: bundleId as NSString)
        return icon
    }

    /// 复盘/叙事用的友好名：bundleId → 应用名（本机装了才翻），URL 串 → host+path，
    /// 其余（纯 host 如 "x.com"、未安装的 bundleId）原样保留——比正则截尾稳。
    static func friendly(_ raw: String) -> String {
        if raw.contains("://"), let url = URL(string: raw), let host = url.host {
            let path = url.path == "/" ? "" : url.path
            return host + path
        }
        if NSWorkspace.shared.urlForApplication(withBundleIdentifier: raw) != nil {
            return displayName(forBundleId: raw)
        }
        return raw
    }

    static func displayName(forBundleId bundleId: String) -> String {
        if let cached = nameCache[bundleId] { return cached }
        let name: String
        if let running = NSWorkspace.shared.runningApplications
            .first(where: { $0.bundleIdentifier == bundleId })?.localizedName {
            name = running
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            name = url.deletingPathExtension().lastPathComponent
        } else {
            name = bundleId // 未安装：显示裸 bundleId
        }
        nameCache[bundleId] = name
        return name
    }
}
