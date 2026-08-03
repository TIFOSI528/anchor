import SwiftUI
import AnchorCore

/// Anchor 设置窗口（PR #27）：通用 / Presets / Friction / 关于。
struct SettingsView: View {
    @ObservedObject var library: PresetLibrary
    weak var coordinator: AppCoordinator?

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label(L("settings.tab.general"), systemImage: "gearshape") }
            PresetsSettingsView(library: library, coordinator: coordinator)
                .tabItem { Label(L("settings.tab.presets"), systemImage: "list.bullet.rectangle") }
            FrictionSettingsView()
                .tabItem { Label(L("settings.tab.friction"), systemImage: "drop") }
            PrivacySettingsView(coordinator: coordinator)
                .tabItem { Label(L("settings.tab.privacy"), systemImage: "lock.shield") }
            AboutSettingsView()
                .tabItem { Label(L("settings.tab.about"), systemImage: "info.circle") }
        }
        // 固定尺寸会在长语言（德/法）下裁掉说明文字，给出理想值并允许长大。
        .frame(minWidth: 520, idealWidth: 560, minHeight: 440, idealHeight: 480)
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
                Toggle(L("settings.general.launch_at_login"), isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in LoginItem.set(enabled) }
                Picker(L("settings.general.island_position"), selection: $islandPosition) {
                    ForEach(IslandPosition.allCases) { pos in
                        Text(pos.label).tag(pos.rawValue)
                    }
                }
                Text(L("settings.general.island_position_note"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Toggle(L("settings.general.haptics"), isOn: $hapticsEnabled)
                Toggle(L("settings.general.hotkeys"), isOn: $hotkeysEnabled)
                Text(L("settings.general.hotkeys_note"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                // 快捷键依赖辅助功能权限；没授权时按下去毫无反应且没有任何提示，
                // 用户只会以为功能坏了。把状态和授权入口摆出来。
                if hotkeysEnabled {
                    PermissionStatusRow(explanation: L("settings.permission.hotkeys_need_access"))
                }
                Toggle(L("settings.general.hide_menu_bar_icon"), isOn: $hideMenuBarIcon)
                    .onChange(of: hideMenuBarIcon) { _, _ in
                        NotificationCenter.default.post(name: .anchorMenuBarIconChanged, object: nil)
                    }
                Text(L("settings.general.hide_menu_bar_icon_note"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Toggle(L("settings.general.auto_update"), isOn: $autoUpdate)
            }

            Section(L("settings.general.extension_section")) {
                HStack {
                    Circle()
                        .fill(extensionConnected ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)
                    Text(extensionConnected
                         ? L("settings.general.extension_connected")
                         : L("settings.general.extension_disconnected"))
                    Spacer()
                    Button(L("settings.general.extension_install_guide")) {
                        NSWorkspace.shared.activateFileViewerSelecting(
                            [URL(fileURLWithPath: extensionPath)]
                        )
                    }
                }
                Text(L("settings.general.extension_note"))
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
    @State private var pendingDeletion: Preset?

    var body: some View {
        Form {
            Section(L("settings.presets.section")) {
                ForEach(library.presets) { preset in
                    HStack {
                        Image(systemName: preset.id == library.activePresetId ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(.tint)
                        VStack(alignment: .leading) {
                            Text(preset.displayName)
                            Text(L("settings.presets.summary",
                                   Int64(preset.greenRules.count),
                                   Int64(preset.redRules.count),
                                   Int64(preset.driftThresholdSeconds)))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(L("settings.presets.edit")) { editing = preset }
                        // 删除场景会丢掉用户攒了很久的规则，且不可撤销——必须先确认。
                        Button(role: .destructive) {
                            pendingDeletion = preset
                        } label: { Image(systemName: "trash") }
                        .disabled(preset.id == library.activePresetId)
                        .help(preset.id == library.activePresetId
                              ? L("settings.presets.delete_disabled_help")
                              : L("settings.presets.delete_help", preset.displayName))
                        .accessibilityLabel(L("settings.presets.delete_accessibility", preset.displayName))
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { library.switchTo(id: preset.id) }
                }
                Button(L("settings.presets.new")) {
                    editing = Preset(id: "user." + UUID().uuidString,
                                     name: L("settings.presets.new_default_name"))
                }
            }

            if showRevert {
                Section {
                    Button(L("settings.presets.revert_suggestion")) {
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
        .confirmationDialog(
            pendingDeletion.map { L("settings.presets.delete_confirm_title", $0.displayName) } ?? "",
            isPresented: .init(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
            titleVisibility: .visible
        ) {
            Button(L("settings.presets.delete_confirm_button"), role: .destructive) {
                if let preset = pendingDeletion { library.delete(id: preset.id) }
                pendingDeletion = nil
            }
            Button(L("settings.presets.delete_cancel"), role: .cancel) { pendingDeletion = nil }
        } message: {
            Text(L("settings.presets.delete_confirm_message"))
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
                TextField(L("preset.editor.name"), text: $name)
                HStack {
                    Text(L("preset.editor.threshold", Int64(threshold)))
                    Slider(value: $threshold, in: 15...300, step: 15)
                }

                Text(L("preset.editor.green_apps")).font(.caption.bold())
                AppChipsView(bundleIds: greenApps) { id in greenApps.removeAll { $0 == id } }
                Text(L("preset.editor.red_apps")).font(.caption.bold())
                AppChipsView(bundleIds: redApps) { id in redApps.removeAll { $0 == id } }

                DisclosureGroup(L("preset.editor.add_from_running")) {
                    RunningAppPicker(
                        greenIds: Set(greenApps),
                        redIds: Set(redApps),
                        onCapture: { id, zone in capture(id, as: zone) }
                    )
                }

                Text(L("preset.editor.green_urls")).font(.caption)
                TextEditor(text: $greenURLText)
                    .font(.system(.caption, design: .monospaced)).frame(height: 70)
                Text(L("preset.editor.red_urls")).font(.caption)
                TextEditor(text: $redURLText)
                    .font(.system(.caption, design: .monospaced)).frame(height: 60)

                HStack {
                    Spacer()
                    Button(L("preset.editor.cancel")) { onDone(nil) }
                    Button(L("preset.editor.save")) { onDone(buildPreset()) }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(16)
        }
        // 固定尺寸会在长语言（德/法）下裁掉说明文字，给出理想值并允许长大。
        .frame(minWidth: 460, idealWidth: 460, minHeight: 540, idealHeight: 540)
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
            name: name.isEmpty ? L("preset.editor.untitled") : name,
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
                Toggle(L("settings.friction.blur"), isOn: $frictionEnabled)
                Toggle(L("settings.friction.serious_mode"), isOn: $seriousMode)
                Toggle(L("settings.friction.scroll_lock"), isOn: $inputFriction)
                // 开关打开但没权限时，之前是彻底静默——用户以为坏了。现在明说。
                if inputFriction {
                    PermissionStatusRow(explanation: L("settings.permission.scroll_lock_need_access"))
                }
            } footer: {
                Text(L("settings.friction.scroll_lock_note"))
            }
            Section(L("settings.friction.accessibility_section")) {
                Toggle(L("settings.friction.reduce_motion"), isOn: $reduceFriction)
                Text(L("settings.friction.accessibility_note"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 隐私与数据

/// 「数据只存本地」要能被用户查证、带走、删掉，否则只是一句口号。
struct PrivacySettingsView: View {
    weak var coordinator: AppCoordinator?

    @AppStorage(SettingsKey.retentionDays) private var retentionDays = SessionStore.defaultRetentionDays
    @State private var confirmingWipe = false
    @State private var statusMessage: String?

    private let retentionOptions = [30, 90, 365, 0]

    var body: some View {
        Form {
            Section(L("settings.privacy.what_section")) {
                Text(L("settings.privacy.what_recorded"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(L("settings.privacy.storage_note"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section(L("settings.privacy.retention_section")) {
                Picker(L("settings.privacy.retention_picker"), selection: $retentionDays) {
                    ForEach(retentionOptions, id: \.self) { days in
                        Text(days == 0
                             ? L("settings.privacy.retention_forever")
                             : L("settings.privacy.retention_days", Int64(days))).tag(days)
                    }
                }
            }

            Section {
                Button(L("settings.privacy.export")) { export() }
                Button(L("settings.privacy.wipe"), role: .destructive) { confirmingWipe = true }
                if let statusMessage {
                    Text(statusMessage).font(.footnote).foregroundStyle(.secondary)
                }
            } footer: {
                Text(L("settings.privacy.wipe_note"))
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            L("settings.privacy.wipe_confirm_title"),
            isPresented: $confirmingWipe,
            titleVisibility: .visible
        ) {
            Button(L("settings.privacy.wipe_confirm_button"), role: .destructive) { wipe() }
            Button(L("settings.privacy.wipe_cancel"), role: .cancel) {}
        } message: {
            Text(L("settings.privacy.wipe_confirm_message"))
        }
    }

    private func export() {
        guard let coordinator else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "anchor-data-\(DayKey.key(for: Date())).json"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        coordinator.exportData(to: url) { error in
            statusMessage = error == nil
                ? L("settings.privacy.export_success", url.lastPathComponent)
                : L("settings.privacy.export_failure", error!.localizedDescription)
        }
    }

    private func wipe() {
        coordinator?.wipeHistory { error in
            statusMessage = error == nil
                ? L("settings.privacy.wipe_success")
                : L("settings.privacy.wipe_failure", error!.localizedDescription)
        }
    }
}

// MARK: - 关于

struct AboutSettingsView: View {
    private var version: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "dev"
    }

    private static let repo = "https://github.com/TIFOSI528/anchor"

    var body: some View {
        VStack(spacing: 10) {
            // 品牌名不翻译。
            Text(verbatim: "⚓︎ Anchor").font(.largeTitle)
            Text(L("settings.about.tagline")).foregroundStyle(.secondary)
            Text(L("settings.about.version", version)).font(.callout).textSelection(.enabled)
            Divider().padding(.vertical, 4)
            Text(L("settings.about.license_line")).font(.footnote)
            // 开源项目的「关于」页此前一个可点链接都没有——用户既无处反馈问题，
            // 也无法核对许可证与隐私说明。
            HStack(spacing: 14) {
                Link(L("settings.about.homepage"), destination: URL(string: Self.repo)!)
                Link(L("settings.about.report_issue"), destination: URL(string: Self.repo + "/issues/new")!)
                Link(L("settings.about.privacy_policy"), destination: URL(string: Self.repo + "/blob/main/PRIVACY.md")!)
                Link(L("settings.about.license"), destination: URL(string: Self.repo + "/blob/main/LICENSE")!)
            }
            .font(.footnote)
            Text(L("settings.about.credits"))
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
    /// 历史数据留存天数；0 = 永久保留。
    static let retentionDays = "anchor.retentionDays"
    /// Sparkle 读这个标准键决定是否自动检查。
    static let autoUpdateEnabled = "SUEnableAutomaticChecks"
}
