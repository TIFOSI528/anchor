import Foundation

/// `Preset` ↔ `PresetRecord`（presets 表）以及规则的文本格式。
///
/// rules_json 形如：`{"green":["app:com.x","url:github.com/*"],"red":["url:x.com/home"]}`。
/// 行格式（`app:` / `url:` 前缀）同时也是 Settings 里手工编辑的格式。
public enum PresetSerialization {

    // MARK: - rule ↔ line

    public static func line(for rule: ZoneRule) -> String {
        switch rule {
        case .app(let bundleId): return "app:\(bundleId)"
        case .url(let pattern): return "url:\(pattern)"
        }
    }

    public static func rule(fromLine raw: String) -> ZoneRule? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("app:") {
            let value = String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespaces)
            return value.isEmpty ? nil : .app(bundleId: value)
        }
        if trimmed.hasPrefix("url:") {
            let value = String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespaces)
            return value.isEmpty ? nil : .url(pattern: value)
        }
        return nil
    }

    // MARK: - rules ↔ JSON

    public static func rulesJSON(green: [ZoneRule], red: [ZoneRule]) -> String {
        let object = ["green": green.map(line(for:)), "red": red.map(line(for:))]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else {
            return #"{"green":[],"red":[]}"#
        }
        return json
    }

    public static func rules(fromJSON json: String) -> (green: [ZoneRule], red: [ZoneRule]) {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: [String]] else {
            return ([], [])
        }
        let green = (object["green"] ?? []).compactMap(rule(fromLine:))
        let red = (object["red"] ?? []).compactMap(rule(fromLine:))
        return (green, red)
    }

    // MARK: - Preset ↔ PresetRecord

    public static func record(from preset: Preset, createdAt: Date, updatedAt: Date) -> PresetRecord {
        PresetRecord(
            id: preset.id,
            name: preset.name,
            rulesJSON: rulesJSON(green: preset.greenRules, red: preset.redRules),
            driftThresholdSeconds: Int(preset.driftThresholdSeconds),
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    public static func preset(from record: PresetRecord) -> Preset {
        let rules = rules(fromJSON: record.rulesJSON)
        return Preset(
            id: record.id,
            name: record.name,
            greenRules: rules.green,
            redRules: rules.red,
            driftThresholdSeconds: TimeInterval(record.driftThresholdSeconds)
        )
    }
}
