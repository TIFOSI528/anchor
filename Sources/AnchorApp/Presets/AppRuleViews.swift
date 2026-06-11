import SwiftUI
import AnchorCore

/// app 规则的图标 chips（点 × 删除）。
struct AppChipsView: View {
    let bundleIds: [String]
    let onRemove: (String) -> Void

    var body: some View {
        if bundleIds.isEmpty {
            Text("还没有应用——从下方「正在运行的应用」点选，或用菜单栏一键收编。")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 6)], alignment: .leading, spacing: 6) {
                ForEach(bundleIds, id: \.self) { bundleId in
                    HStack(spacing: 5) {
                        Image(nsImage: AppIconProvider.icon(forBundleId: bundleId))
                        Text(AppIconProvider.displayName(forBundleId: bundleId))
                            .font(.caption)
                            .lineLimit(1)
                        Button {
                            onRemove(bundleId)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("移除 \(AppIconProvider.displayName(forBundleId: bundleId))")
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary.opacity(0.5), in: Capsule())
                }
            }
        }
    }
}

/// 正在运行的应用选择器：点「绿」/「红」收编，再点一次取消（放回灰区）。
struct RunningAppPicker: View {
    let greenIds: Set<String>
    let redIds: Set<String>
    /// zone: .green / .red / .gray（取消）
    let onCapture: (String, ZoneClassification) -> Void

    @State private var apps: [(id: String, name: String)] = []

    var body: some View {
        ScrollView {
            VStack(spacing: 2) {
                ForEach(apps, id: \.id) { app in
                    HStack(spacing: 8) {
                        Image(nsImage: AppIconProvider.icon(forBundleId: app.id))
                        Text(app.name).font(.callout).lineLimit(1)
                        Spacer()
                        zoneButton("绿", active: greenIds.contains(app.id), tint: .green) {
                            onCapture(app.id, greenIds.contains(app.id) ? .gray : .green)
                        }
                        zoneButton("红", active: redIds.contains(app.id), tint: .red) {
                            onCapture(app.id, redIds.contains(app.id) ? .gray : .red)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .frame(maxHeight: 150)
        .onAppear(perform: load)
    }

    private func zoneButton(_ label: String, active: Bool, tint: Color, action: @escaping () -> Void) -> some View {
        Button(label, action: action)
            .buttonStyle(.bordered)
            .tint(active ? tint : .secondary)
            .controlSize(.small)
            .fontWeight(active ? .bold : .regular)
    }

    private func load() {
        apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in
                guard let id = app.bundleIdentifier, id != Bundle.main.bundleIdentifier else { return nil }
                return (id: id, name: app.localizedName ?? id)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
