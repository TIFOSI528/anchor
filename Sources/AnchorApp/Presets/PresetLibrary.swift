import Foundation
import AnchorCore

/// DB 持久化的 preset 库（PR #8 + PR #27 Presets tab 的数据源）。
///
/// 首次启动把内置 preset 种进 `presets` 表；之后以 DB 为准。
/// 写操作在 `writeQueue` 上异步执行（SQLite 写不阻塞主线程）。
@MainActor
final class PresetLibrary: ObservableObject {

    @Published private(set) var presets: [Preset] = BuiltinPresets.all
    @Published private(set) var activePresetId: String

    /// active preset 变化（含规则被编辑）时通知 coordinator。
    var onActivePresetChange: ((Preset) -> Void)?

    private let store: SessionStore?
    private let writeQueue: DispatchQueue
    private static let activeKey = "anchor.activePresetId"

    var activePreset: Preset {
        presets.first { $0.id == activePresetId } ?? presets.first ?? BuiltinPresets.casualMode
    }

    init(store: SessionStore?, writeQueue: DispatchQueue) {
        self.store = store
        self.writeQueue = writeQueue
        self.activePresetId = UserDefaults.standard.string(forKey: Self.activeKey)
            ?? BuiltinPresets.writeCode.id
        loadOrSeed()
    }

    func switchTo(id: String) {
        guard presets.contains(where: { $0.id == id }) else { return }
        activePresetId = id
        UserDefaults.standard.set(id, forKey: Self.activeKey)
        onActivePresetChange?(activePreset)
    }

    /// 新建或更新（id 相同即更新）。
    func upsert(_ preset: Preset) {
        if let index = presets.firstIndex(where: { $0.id == preset.id }) {
            presets[index] = preset
        } else {
            presets.append(preset)
        }
        persist(preset)
        if preset.id == activePresetId {
            onActivePresetChange?(preset)
        }
    }

    func delete(id: String) {
        guard id != activePresetId, presets.count > 1 else { return }
        presets.removeAll { $0.id == id }
        guard let store else { return }
        writeQueue.async { try? store.deletePreset(id: id) }
    }

    /// 一键收编：把 app 收进 active preset 的指定区（互斥语义见 `Preset.capturing`）。
    func capture(bundleId: String, as zone: ZoneClassification) {
        upsert(activePreset.capturing(bundleId: bundleId, as: zone))
    }

    /// 一键收编（站点版）：浏览器前台且已知 tab 时收编 url pattern。
    func captureURL(pattern: String, as zone: ZoneClassification) {
        upsert(activePreset.capturing(urlPattern: pattern, as: zone))
    }

    /// 给 active preset 加一条黑名单规则（周建议规则 A 的一键 apply）。
    func appendRedRule(_ rule: ZoneRule) {
        var preset = activePreset
        guard !preset.redRules.contains(rule) else { return }
        preset.redRules.append(rule)
        upsert(preset)
    }

    /// 把某条规则从 active preset 的绿区移除（周建议规则 B：绿 → 灰）。
    func removeGreenRule(_ rule: ZoneRule) {
        var preset = activePreset
        preset.greenRules.removeAll { $0 == rule }
        upsert(preset)
    }

    // MARK: - private

    private func loadOrSeed() {
        guard let store else { return }
        if let records = try? store.presets(), !records.isEmpty {
            presets = records.map(PresetSerialization.preset(from:))
        } else {
            let now = Date()
            for preset in BuiltinPresets.all {
                let record = PresetSerialization.record(from: preset, createdAt: now, updatedAt: now)
                writeQueue.async { try? store.upsertPreset(record) }
            }
        }
        if !presets.contains(where: { $0.id == activePresetId }) {
            activePresetId = presets.first?.id ?? BuiltinPresets.writeCode.id
        }
    }

    private func persist(_ preset: Preset) {
        guard let store else { return }
        let record = PresetSerialization.record(from: preset, createdAt: Date(), updatedAt: Date())
        writeQueue.async { try? store.upsertPreset(record) }
    }
}
