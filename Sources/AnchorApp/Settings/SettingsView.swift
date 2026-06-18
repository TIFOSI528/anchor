import SwiftUI
import AnchorCore

/// Anchor 设置窗口（PR #27）：通用 / Presets / Friction / 关于。
struct SettingsView: View {
    @ObservedObject var library: PresetLibrary
    weak var coordinator: AppCoordinator?

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("通用", systemImage: "gearshape") }
            PresetsSettingsView(library: library, coordinator: coordinator)
                .tabItem { Label("场景", systemImage: "list.bullet.rectangle") }
            FrictionSettingsView()
                .tabItem { Label("摩擦", systemImage: "drop") }
            AboutSettingsView()
                .tabItem { Label("关于", systemImage: "info.circle") }
        }
        .frame(width: 520, height: 440)
    }
}

// MARK: - 通用

struct GeneralSettingsView: View {
    @AppStorage(SettingsKey.launchAtLogin) private var launchAtLogin = false
    @AppStorage(SettingsKey.islandPosition) private var islandPosition = IslandPosition.auto.rawValue
    @AppStorage(SettingsKey.hapticsEnabled) private var hapticsEnabled = true
    @AppStorage(SettingsKey.hotkeysEnabled) private var hotkeysEnabled = true
    @AppStorage(SettingsKey.hideMenuBarIcon) private var hideMenuBarIcon = false
    @AppStorage(SettingsKey.autoUpdateEnabled) private var autoUpdate = false
    @AppStorage(SettingsKey.extensionConnected) private var extensionConnected = false

    var body: some View {
        Form {
            Section {
                Toggle("开机自动启动", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in LoginItem.set(enabled) }
                Picker("灵动岛位置", selection: $islandPosition) {
                    ForEach(IslandPosition.allCases) { pos in
                        Text(pos.label).tag(pos.rawValue)
                    }
                }
                Text("位置更改后重启 Anchor 生效。无刘海机型「自动」即菜单栏嵌入：空闲只占一个小圆点且点击穿透，不遮挡系统状态图标；漂移展开时才临时变宽。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Toggle("手势触感反馈", isOn: $hapticsEnabled)
                Toggle("全局快捷键（⌃⌥⌘ A/B/L/P）", isOn: $hotkeysEnabled)
                Text("与其它应用冲突时可整体关闭（重启生效）；菜单与岛上入口不受影响。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Toggle("隐藏菜单栏图标", isOn: $hideMenuBarIcon)
                    .onChange(of: hideMenuBarIcon) { _, _ in
                        NotificationCenter.default.post(name: .anchorMenuBarIconChanged, object: nil)
                    }
                Text("菜单栏太挤可关掉图标——左键绿点、或在任何状态右键灵动岛，都能打开完整菜单。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Toggle("自动检查更新", isOn: $autoUpdate)
            }

            Section("浏览器扩展") {
                HStack {
                    Circle()
                        .fill(extensionConnected ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)
                    Text(extensionConnected ? "已连接" : "未连接")
                    Spacer()
                    Button("安装指南") {
                        NSWorkspace.shared.activateFileViewerSelecting(
                            [URL(fileURLWithPath: extensionPath)]
                        )
                    }
                }
                Text("Chrome → chrome://extensions → 开发者模式 → 加载已解压的扩展程序 → 选中上面目录。tab 级判定（如「GitHub 自己的仓库绿、trending 红」）需要扩展。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var extensionPath: String {
        // 打包后扩展在 Resources；开发态指向源码目录。
        let bundled = Bundle.main.resourcePath.map { $0 + "/AnchorExtension/chrome" }
        if let bundled, FileManager.default.fileExists(atPath: bundled) { return bundled }
        return FileManager.default.currentDirectoryPath + "/Sources/AnchorExtension/chrome"
    }
}

// MARK: - Presets

struct PresetsSettingsView: View {
    @ObservedObject var library: PresetLibrary
    weak var coordinator: AppCoordinator?

    @State private var editing: Preset?
    @State private var showRevert = UserDefaults.standard.dictionary(forKey: SettingsKey.lastSuggestion) != nil

    var body: some View {
        Form {
            Section("场景（点选切换）") {
                ForEach(library.presets) { preset in
                    HStack {
                        Image(systemName: preset.id == library.activePresetId ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(.tint)
                        VStack(alignment: .leading) {
                            Text(preset.name)
                            Text("绿 \(preset.greenRules.count) · 红 \(preset.redRules.count) · 倒计时 \(Int(preset.driftThresholdSeconds))s")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("编辑") { editing = preset }
                        Button(role: .destructive) {
                            library.delete(id: preset.id)
                        } label: { Image(systemName: "trash") }
                        .disabled(preset.id == library.activePresetId)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { library.switchTo(id: preset.id) }
                }
                Button("新建场景...") {
                    editing = Preset(id: "user." + UUID().uuidString, name: "新场景")
                }
            }

            if showRevert {
                Section {
                    Button("撤销上周建议的修改") {
                        coordinator?.revertLastSuggestion()
                        showRevert = false
                    }
                }
            }
        }
        .formStyle(.grouped)
        .sheet(item: $editing) { preset in
            PresetEditor(preset: preset) { updated in
                if let updated { library.upsert(updated) }
                editing = nil
            }
        }
    }
}

/// Preset 编辑器：app 规则用图标 chips + 运行中应用选择器，URL 规则保持文本行。
/// 设计稿：docs/plans/2026-06-10-preset-icon-editor-design.md。
struct PresetEditor: View {
    @State var name: String
    @State var threshold: Double
    @State var greenApps: [String]
    @State var redApps: [String]
    @State var greenURLText: String
    @State var redURLText: String
    let presetId: String
    let onDone: (Preset?) -> Void

    init(preset: Preset, onDone: @escaping (Preset?) -> Void) {
        self.presetId = preset.id
        self.onDone = onDone
        _name = State(initialValue: preset.name)
        _threshold = State(initialValue: preset.driftThresholdSeconds)
        _greenApps = State(initialValue: Self.appIds(of: preset.greenRules))
        _redApps = State(initialValue: Self.appIds(of: preset.redRules))
        _greenURLText = State(initialValue: Self.urlLines(of: preset.greenRules))
        _redURLText = State(initialValue: Self.urlLines(of: preset.redRules))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                TextField("名称", text: $name)
                HStack {
                    Text("漂移倒计时 \(Int(threshold))s")
                    Slider(value: $threshold, in: 15...300, step: 15)
                }

                Text("绿区应用").font(.caption.bold())
                AppChipsView(bundleIds: greenApps) { id in greenApps.removeAll { $0 == id } }
                Text("红区应用").font(.caption.bold())
                AppChipsView(bundleIds: redApps) { id in redApps.removeAll { $0 == id } }

                DisclosureGroup("从正在运行的应用添加") {
                    RunningAppPicker(
                        greenIds: Set(greenApps),
                        redIds: Set(redApps),
                        onCapture: { id, zone in capture(id, as: zone) }
                    )
                }

                Text("绿区 URL 规则（一行一条，支持 *；浏览器 tab 级控制用这里）").font(.caption)
                TextEditor(text: $greenURLText)
                    .font(.system(.caption, design: .monospaced)).frame(height: 70)
                Text("红区 URL 规则").font(.caption)
                TextEditor(text: $redURLText)
                    .font(.system(.caption, design: .monospaced)).frame(height: 60)

                HStack {
                    Spacer()
                    Button("取消") { onDone(nil) }
                    Button("保存") { onDone(buildPreset()) }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(16)
        }
        .frame(width: 460, height: 540)
    }

    /// 编辑器内同样执行互斥语义（与 Preset.capturing 一致）。
    private func capture(_ bundleId: String, as zone: ZoneClassification) {
        greenApps.removeAll { $0 == bundleId }
        redApps.removeAll { $0 == bundleId }
        switch zone {
        case .green: greenApps.append(bundleId)
        case .red: redApps.append(bundleId)
        case .gray: break
        }
    }

    private func buildPreset() -> Preset {
        Preset(
            id: presetId,
            name: name.isEmpty ? "未命名" : name,
            greenRules: greenApps.map { .app(bundleId: $0) } + Self.urlRules(from: greenURLText),
            redRules: redApps.map { .app(bundleId: $0) } + Self.urlRules(from: redURLText),
            driftThresholdSeconds: threshold
        )
    }

    // MARK: - rule helpers

    private static func appIds(of rules: [ZoneRule]) -> [String] {
        rules.compactMap { if case let .app(id) = $0 { return id } else { return nil } }
    }

    private static func urlLines(of rules: [ZoneRule]) -> String {
        rules.compactMap { if case let .url(pattern) = $0 { return pattern } else { return nil } }
            .joined(separator: "\n")
    }

    /// 接受裸 pattern 或带 `url:` 前缀的行。
    private static func urlRules(from text: String) -> [ZoneRule] {
        text.split(separator: "\n").compactMap { raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { return nil }
            if let rule = PresetSerialization.rule(fromLine: line) {
                if case .url = rule { return rule }
                return rule // app: 行也容忍（老格式粘贴）
            }
            return .url(pattern: line)
        }
    }
}

// MARK: - Friction

struct FrictionSettingsView: View {
    @AppStorage(SettingsKey.frictionEnabled) private var frictionEnabled = true
    @AppStorage(SettingsKey.seriousMode) private var seriousMode = false
    @AppStorage(SettingsKey.reduceFriction) private var reduceFriction = false
    @AppStorage(SettingsKey.inputFrictionEnabled) private var inputFriction = false

    var body: some View {
        Form {
            Section {
                Toggle("漂移时屏幕渐进模糊（摩擦雾）", isOn: $frictionEnabled)
                Toggle("严肃模式（关闭复盘自嘲文案）", isOn: $seriousMode)
                Toggle("深度漂移时锁定滚动（需辅助功能权限）", isOn: $inputFriction)
            } footer: {
                Text("滚动锁默认关闭；开启后仅在漂移超过 3 分钟时生效，随时可在这里关掉。")
            }
            Section("无障碍") {
                Toggle("减少动态效果（不模糊屏幕，仅保留轻提示）", isOn: $reduceFriction)
                Text("无障碍是底线：所有摩擦干预都能在这里一键关掉。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 关于

struct AboutSettingsView: View {
    private var version: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "dev"
    }

    var body: some View {
        VStack(spacing: 10) {
            Text("⚓︎ Anchor").font(.largeTitle)
            Text("桅杆上的瞭望员").foregroundStyle(.secondary)
            Text("版本 \(version)").font(.callout)
            Divider().padding(.vertical, 4)
            Text("GPL-3.0 · Local-first · 无遥测").font(.footnote)
            Text("致谢：DynamicNotchKit · Sparkle · SQLite.swift")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.top, 28)
        .frame(maxWidth: .infinity)
    }
}

extension Notification.Name {
    /// 「隐藏菜单栏图标」开关变化 → AppDelegate 即时同步 statusItem.isVisible。
    static let anchorMenuBarIconChanged = Notification.Name("anchor.menuBarIconChanged")
}

/// UserDefaults 键名集中管理。
enum SettingsKey {
    static let launchAtLogin = "anchor.launchAtLogin"
    static let islandPosition = "anchor.islandPosition"
    static let hapticsEnabled = "anchor.hapticsEnabled"
    static let hotkeysEnabled = "anchor.hotkeysEnabled"
    static let hideMenuBarIcon = "anchor.hideMenuBarIcon"
    static let frictionEnabled = "anchor.frictionEnabled"
    static let seriousMode = "anchor.seriousMode"
    static let reduceFriction = "anchor.reduceFriction"
    static let inputFrictionEnabled = "anchor.inputFrictionEnabled"
    static let extensionConnected = "anchor.extensionConnected"
    static let lastSuggestion = "anchor.lastSuggestion"
    /// Sparkle 读这个标准键决定是否自动检查。
    static let autoUpdateEnabled = "SUEnableAutomaticChecks"
}
