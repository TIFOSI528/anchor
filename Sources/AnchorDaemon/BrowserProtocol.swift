import Foundation

/// 扩展 ↔ Daemon 的 line-delimited JSON 协议编解码（见 technical-architecture §四）。
///
/// 不变量：**协议向后兼容**——扩展和 app 版本可能不一致，未知 type / 缺字段一律静默忽略（返回 nil），
/// 绝不 crash。
public enum BrowserProtocol {

    /// 解析一行 JSON → `BrowserEvent`。未知 type、字段缺失或格式错误都返回 nil。
    public static func decodeEvent(_ line: String) -> BrowserEvent? {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String else {
            return nil
        }

        switch type {
        case "hello":
            guard let browser = obj["browser"] as? String,
                  let version = obj["version"] as? String else { return nil }
            return .hello(browser: browser, version: version)

        case "tab_active":
            guard let browser = obj["browser"] as? String,
                  let urlString = obj["url"] as? String,
                  let url = URL(string: urlString),
                  let windowId = (obj["window_id"] as? NSNumber)?.intValue,
                  let tabId = (obj["tab_id"] as? NSNumber)?.intValue,
                  let timestamp = (obj["timestamp"] as? NSNumber)?.doubleValue else { return nil }
            return .tabActive(
                browser: browser, url: url, windowId: windowId, tabId: tabId,
                timestamp: Date(timeIntervalSince1970: timestamp)
            )

        case "browser_blurred":
            guard let browser = obj["browser"] as? String,
                  let timestamp = (obj["timestamp"] as? NSNumber)?.doubleValue else { return nil }
            return .browserBlurred(browser: browser, timestamp: Date(timeIntervalSince1970: timestamp))

        case "heartbeat":
            guard let browser = obj["browser"] as? String else { return nil }
            return .heartbeat(browser: browser)

        default:
            return nil // 未知 type：向后兼容，静默忽略
        }
    }

    /// `BrowserCommand` → 一行 JSON（含结尾换行符，line-delimited）。
    public static func encodeCommand(_ command: BrowserCommand) -> String {
        let object: [String: Any]
        switch command {
        case let .navigate(url):
            object = ["type": "navigate", "url": url.absoluteString]
        case let .frictionOverlay(level):
            object = ["type": "friction_overlay", "level": level]
        case .frictionClear:
            object = ["type": "friction_clear"]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let json = String(data: data, encoding: .utf8) else {
            return "{}\n"
        }
        return json + "\n"
    }
}

/// 把 socket 读到的字节流按 `\n` 切成完整行；不完整的尾部留在 buffer 里等下次。
public struct LineBuffer {

    private var buffer = ""

    public init() {}

    /// 追加一段收到的数据，返回其中已完整的行（不含换行符）。
    public mutating func append(_ chunk: String) -> [String] {
        buffer += chunk
        var lines: [String] = []
        while let newline = buffer.firstIndex(of: "\n") {
            lines.append(String(buffer[..<newline]))
            buffer = String(buffer[buffer.index(after: newline)...])
        }
        return lines
    }

    /// 当前缓存的未完成尾部（主要给测试 / 调试看）。
    public var pending: String { buffer }
}
