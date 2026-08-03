import SwiftUI
import AppKit
import AnchorCore

/// 首启引导。
///
/// **为什么必须有**：此前装完没有任何欢迎流程，而产品的全部词汇（绿区 / 灰区 / 红区 /
/// 漂移 / 合法摸鱼）从未向用户解释过，三个手势也没有任何地方教。新用户能看到的第一个
/// "功能"往往是屏幕开始起雾——读起来像故障，不像设计。
///
/// 四步都可跳过，且顺序是刻意的：先解释语言，再选场景（让绿区真的有东西），
/// 最后才是两个**可选**权限/扩展。权限绝不在启动时偷偷请求。
struct OnboardingView: View {
    @ObservedObject var library: PresetLibrary
    @ObservedObject private var permissions = PermissionCenter.shared
    @AppStorage(SettingsKey.extensionConnected) private var extensionConnected = false

    let onFinish: () -> Void

    @State private var page = 0
    private let pageCount = 4

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(28)

            Divider()
            footer
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
        }
        .frame(width: 560, height: 480)
    }

    @ViewBuilder
    private var content: some View {
        switch page {
        case 0: welcomePage
        case 1: scenePage
        case 2: extensionPage
        default: shortcutsPage
        }
    }

    // MARK: - 1. 这是什么

    private var welcomePage: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L("onboarding.welcome.title")).font(.largeTitle.bold())
            Text(L("onboarding.welcome.subtitle"))
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 12) {
                // 同时教"颜色 + 形状"两套线索——菜单栏那颗点就是这么编码的，
                // 色盲用户靠形状也能读出状态。
                zoneRow(color: Color(hex: 0x22C55E), glyph: nil,
                        title: L("onboarding.zone.green.title"),
                        detail: L("onboarding.zone.green.detail"))
                zoneRow(color: Color(hex: 0xF59E0B), glyph: "exclamationmark",
                        title: L("onboarding.zone.gray.title"),
                        detail: L("onboarding.zone.gray.detail"))
                zoneRow(color: Color(hex: 0xDC2626), glyph: "xmark",
                        title: L("onboarding.zone.red.title"),
                        detail: L("onboarding.zone.red.detail"))
            }
            .padding(.vertical, 4)

            Label(L("onboarding.welcome.escape_hatch"), systemImage: "cup.and.saucer")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func zoneRow(color: Color, glyph: String?, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle().fill(color).frame(width: 12, height: 12)
                if let glyph {
                    Image(systemName: glyph)
                        .font(.system(size: 7, weight: .black))
                        .foregroundStyle(.black.opacity(0.75))
                }
            }
            .padding(.top, 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout.weight(.semibold))
                Text(detail).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - 2. 选场景

    private var scenePage: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("onboarding.scene.title")).font(.title.bold())
            Text(L("onboarding.scene.subtitle"))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(library.presets) { preset in
                sceneRow(preset)
            }

            Text(L("onboarding.scene.footnote"))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 单独抽出来：内联在 `ForEach` 里会让类型检查器超时（SwiftUI 嵌套三元 + 泛型推断）。
    private func sceneRow(_ preset: Preset) -> some View {
        let isActive: Bool = preset.id == library.activePresetId
        let subtitle: String = preset.isObserveOnly
            ? L("onboarding.scene.observe_only")
            : L("onboarding.scene.rule_count",
                Int64(preset.greenRules.count),
                Int64(preset.redRules.count))
        return Button {
            library.switchTo(id: preset.id)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isActive ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(preset.displayName).font(.callout.weight(.semibold))
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - 3. 浏览器扩展（可选）

    private var extensionPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("onboarding.extension.title")).font(.title.bold())
            Text(L("onboarding.extension.subtitle"))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                stepRow(1, L("onboarding.extension.step1"))
                // Chrome 不允许外部深链到 chrome://extensions，所以只能给可复制的地址。
                HStack(spacing: 8) {
                    Text("chrome://extensions")
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                    Button(L("onboarding.extension.copy")) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("chrome://extensions", forType: .string)
                    }
                    .controlSize(.small)
                }
                .padding(.leading, 22)
                stepRow(2, L("onboarding.extension.step2"))
                stepRow(3, L("onboarding.extension.step3"))
                Button(L("onboarding.extension.reveal")) {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: Self.extensionPath)])
                }
                .controlSize(.small)
                .padding(.leading, 22)
            }

            HStack(spacing: 6) {
                Circle()
                    .fill(extensionConnected ? Color.green : Color.secondary)
                    .frame(width: 8, height: 8)
                Image(systemName: extensionConnected ? "checkmark" : "ellipsis")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                Text(extensionConnected
                     ? L("onboarding.extension.connected")
                     : L("onboarding.extension.waiting"))
                    .font(.callout)
            }
            .padding(.top, 2)

            Text(L("onboarding.extension.optional"))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func stepRow(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number).").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
        }
    }

    static var extensionPath: String {
        let bundled = Bundle.main.resourcePath.map { $0 + "/AnchorExtension/chrome" }
        if let bundled, FileManager.default.fileExists(atPath: bundled) { return bundled }
        return FileManager.default.currentDirectoryPath + "/Sources/AnchorExtension/chrome"
    }

    // MARK: - 4. 快捷键权限（可选）

    private var shortcutsPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("onboarding.shortcuts.title")).font(.title.bold())
            Text(L("onboarding.shortcuts.subtitle"))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                shortcutRow("⌃⌥⌘A", L("onboarding.shortcuts.snap_back"))
                shortcutRow("⌃⌥⌘B", L("onboarding.shortcuts.slack"))
                shortcutRow("⌃⌥⌘L", L("onboarding.shortcuts.lock"))
                shortcutRow("⌃⌥⌘P", L("onboarding.shortcuts.pause"))
            }

            // 明说这条权限用来干什么、以及不给会怎样——这是信任问题，不是配置问题。
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: statusIcon)
                            .foregroundStyle(statusTint)
                        Text(statusText).font(.callout.weight(.medium))
                    }
                    Text(L("onboarding.shortcuts.rationale"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        if permissions.inputMonitoring != .granted {
                            Button(L("onboarding.shortcuts.grant")) {
                                permissions.requestInputMonitoring()
                            }
                            Button(L("onboarding.shortcuts.open_settings")) {
                                permissions.openSystemSettings()
                            }
                            .controlSize(.small)
                        }
                    }
                }
                .padding(4)
            }

            Text(L("onboarding.shortcuts.optional"))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func shortcutRow(_ keys: String, _ label: String) -> some View {
        HStack(spacing: 10) {
            Text(keys)
                .font(.system(.callout, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
            Text(label).font(.callout)
        }
    }

    private var statusIcon: String {
        switch permissions.inputMonitoring {
        case .granted: return "checkmark.circle.fill"
        case .denied: return "exclamationmark.triangle.fill"
        case .notDetermined: return "questionmark.circle"
        }
    }

    private var statusTint: Color {
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

    // MARK: - footer

    private var footer: some View {
        HStack {
            // 页码点：也是"还有几步"的进度信号。
            HStack(spacing: 5) {
                ForEach(0..<pageCount, id: \.self) { index in
                    Circle()
                        .fill(index == page ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 6, height: 6)
                }
            }
            .accessibilityLabel(L("onboarding.progress", Int64(page + 1), Int64(pageCount)))

            Spacer()

            if page > 0 {
                Button(L("onboarding.back")) { page -= 1 }
            }
            if page < pageCount - 1 {
                // 跳过必须一直在：引导本身也要留逃生通道。
                Button(L("onboarding.skip")) { onFinish() }
                Button(L("onboarding.next")) { page += 1 }
                    .keyboardShortcut(.defaultAction)
            } else {
                Button(L("onboarding.done")) { onFinish() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}
