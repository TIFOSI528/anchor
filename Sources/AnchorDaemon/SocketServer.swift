import Foundation
import Network
import AnchorCore

/// 本机 WebSocket 服务器。监听浏览器扩展发来的事件（PR #18）。
///
/// 传输层说明：technical-architecture §IV 最初写的是 Unix Domain Socket，但 Chrome MV3
/// 扩展只能用 WebSocket（dynamic-island-spec §六 也写明 WebSocket），所以这里监听
/// `ws://127.0.0.1:<port>`，**只绑定 loopback**，消息体 JSON 与 §IV 完全一致
/// （编解码见 `BrowserProtocol`，已单测）。
///
/// 线程模型：所有内部状态都在 `queue` 上访问；`handler` 也在 `queue` 上回调，
/// 调用方（AppCoordinator）需自行 hop 回主线程。
/// `@unchecked Sendable`：所有可变状态都只在内部串行 `queue` 上访问（见各方法注释）。
public final class SocketServer: @unchecked Sendable {

    /// 默认端口。扩展端 `socket_client.js` 的 DEFAULT_PORT 必须与此一致。
    public static let defaultPort: UInt16 = 17604

    /// 心跳约 30s 一次（MV3 alarms 的最小粒度）；超过 75s（2.5 个周期）没消息视为僵尸连接。
    /// （§IV 原文的 "5 秒" 与 30s 心跳互相矛盾——按 30s 心跳推导，见 docs 修订。）
    public static let staleTimeout: TimeInterval = 75

    /// 没能在这个时间内报出合法 `hello` 的连接会被踢掉——挡住"占着连接不说话"的探测者。
    public static let helloTimeout: TimeInterval = 10

    /// 同时在线连接上限。正常只有 1–2 个浏览器；留余量但不给"开几百条连接吃内存"的空间。
    public static let maxClients = 8

    /// 单条消息字节上限。真实事件 JSON < 1KB；超限直接丢弃，不进解析。
    public static let maxMessageBytes = 64 * 1024

    public typealias EventHandler = @Sendable (BrowserEvent) -> Void

    /// `@unchecked Sendable`：仅在 `queue` 上读写。
    private final class Client: @unchecked Sendable {
        let connection: NWConnection
        var browser: String?
        var lastSeen = Date()
        let acceptedAt = Date()
        init(connection: NWConnection) { self.connection = connection }
    }

    /// 握手时的来源判定。
    ///
    /// **为什么必须挡**：Chrome 把 `127.0.0.1` 视为可信来源，所以任意 `https://` 页面都能
    /// `new WebSocket("ws://127.0.0.1:17604")` 连上来。一旦连上，它可以伪造 `tab_active`
    /// 事件（污染漂移库、把自己伪装成绿区来消掉 friction），也会收到广播指令
    /// （其中 `navigate` 带着用户最近的绿区 URL）。
    ///
    /// **为什么用"黑名单"而不是"白名单"**：浏览器扩展发什么 Origin 由浏览器决定，
    /// 各家/各版本不完全一致（可能是 `chrome-extension://<id>`，也可能压根不发）。
    /// 白名单一旦对不上就会把产品核心功能整个打死；而网页来源是**可证伪**的——
    /// 只要带 `http(s)://` 或不透明的 `null`，就一定不是我们的扩展。
    /// 于是：**能证明是网页的一律拒，其余放行**，既堵死攻击面又不会误杀扩展。
    static func isAcceptableOrigin(_ origin: String?) -> Bool {
        // 完全没有 Origin 头：非浏览器客户端（含可能不发该头的扩展宿主）——放行。
        guard let origin else { return true }
        let value = origin.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.isEmpty { return true }
        // 浏览器扩展页面：明确放行。
        for prefix in ["chrome-extension://", "moz-extension://", "safari-web-extension://", "extension://"]
        where value.hasPrefix(prefix) {
            return true
        }
        // 普通网页（含 sandbox iframe 的不透明来源 "null"）：拒。
        return false
    }

    private let handler: EventHandler
    private let requestedPort: UInt16
    private let queue = DispatchQueue(label: "com.anchor.daemon.socket")
    private var listener: NWListener?
    private var clients: [ObjectIdentifier: Client] = [:]
    private var sweepTimer: DispatchSourceTimer?

    /// 实际绑定的端口（start 成功后可读；传 0 时为系统分配的临时端口）。
    public private(set) var boundPort: UInt16?

    /// 是否有任意浏览器扩展在线（Settings 显示连接状态用）。在 queue 外读取是近似值，可接受。
    public private(set) var hasActiveBrowser = false

    /// 连接状态变化回调（true = 至少一个扩展在线）。在内部 queue 上回调。
    public var onBrowserPresenceChange: (@Sendable (Bool) -> Void)?

    public init(port: UInt16 = SocketServer.defaultPort, handler: @escaping EventHandler) {
        self.requestedPort = port
        self.handler = handler
    }

    public func start() throws {
        let parameters = NWParameters.tcp
        // 只听本机回环——绝不暴露到局域网。
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: .ipv4(.loopback),
            port: NWEndpoint.Port(rawValue: requestedPort) ?? .any
        )
        let wsOptions = NWProtocolWebSocket.Options()
        wsOptions.autoReplyPing = true
        wsOptions.maximumMessageSize = Self.maxMessageBytes
        // 握手阶段就按 Origin 拒掉网页来源（见 isAcceptableOrigin）——不让它进到 accept()。
        wsOptions.setClientRequestHandler(queue) { subprotocols, headers in
            let origin = headers.first { $0.name.lowercased() == "origin" }?.value
            guard SocketServer.isAcceptableOrigin(origin) else {
                NSLog("[Anchor] daemon rejected websocket handshake from origin: %@", origin ?? "<none>")
                return NWProtocolWebSocket.Response(status: .reject, subprotocol: nil)
            }
            return NWProtocolWebSocket.Response(status: .accept, subprotocol: subprotocols.first)
        }
        parameters.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)

        let listener = try NWListener(using: parameters)
        self.listener = listener

        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            if case .ready = state {
                self.boundPort = listener.port?.rawValue
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            self.queue.async { self.accept(connection) }
        }
        listener.start(queue: queue)
        startSweepTimer()
    }

    public func stop() {
        queue.sync {
            sweepTimer?.cancel()
            sweepTimer = nil
            for client in clients.values {
                client.connection.cancel()
            }
            clients.removeAll()
            listener?.cancel()
            listener = nil
            updatePresence()
        }
    }

    /// 主动给某个浏览器发指令（拉回 / overlay / clear）。找不到该浏览器时静默丢弃。
    public func send(command: BrowserCommand, to browser: String) {
        queue.async { [weak self] in
            // 取"最近有消息"的那条，而不是字典里碰巧排第一的（见 register 的同名去重）。
            guard let self,
                  let client = self.clients.values
                      .filter({ $0.browser == browser })
                      .max(by: { $0.lastSeen < $1.lastSeen }) else { return }
            self.send(text: BrowserProtocol.encodeCommand(command), over: client.connection)
        }
    }

    /// 给所有在线浏览器广播指令（friction overlay/clear 用）。
    public func broadcast(command: BrowserCommand) {
        queue.async { [weak self] in
            guard let self else { return }
            let text = BrowserProtocol.encodeCommand(command)
            for client in self.clients.values where client.browser != nil {
                self.send(text: text, over: client.connection)
            }
        }
    }

    // MARK: - private (all on `queue`)

    private func accept(_ connection: NWConnection) {
        // 连接数封顶。**不能简单拒新**：否则任何本机进程占满 8 个坑就能把真扩展锁在门外，
        // 用户只会看到"未连接"而无从得知原因。所以满了就先踢掉最没有身份的那个
        // （还没报 hello 的、最早接进来的），把坑让给新来者。
        if clients.count >= Self.maxClients {
            let evictable = clients.values
                .filter { $0.browser == nil }
                .min { $0.acceptedAt < $1.acceptedAt }
                ?? clients.values.min { $0.lastSeen < $1.lastSeen }
            guard let evictable else {
                connection.cancel()
                return
            }
            NSLog("[Anchor] daemon at client limit — evicting stalest connection to admit a new one")
            drop(evictable.connection)
        }
        let client = Client(connection: connection)
        clients[ObjectIdentifier(connection)] = client
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection else { return }
            switch state {
            case .failed, .cancelled:
                self.queue.async { self.drop(connection) }
            default:
                break
            }
        }
        connection.start(queue: queue)
        receiveNext(on: client)
    }

    private func receiveNext(on client: Client) {
        client.connection.receiveMessage { [weak self, weak client] data, _, _, error in
            guard let self, let client else { return }
            if error != nil {
                self.drop(client.connection)
                return
            }
            if let data, data.count <= Self.maxMessageBytes, let text = String(data: data, encoding: .utf8) {
                client.lastSeen = Date()
                // WS 一条消息即一条完整 JSON；line-delimited 兼容多行拼包。
                for line in text.split(separator: "\n") {
                    if let event = BrowserProtocol.decodeEvent(String(line)) {
                        self.register(event, for: client)
                        self.handler(event)
                    }
                }
            }
            self.receiveNext(on: client)
        }
    }

    private func register(_ event: BrowserEvent, for client: Client) {
        switch event {
        case let .hello(browser, _),
             let .tabActive(browser, _, _, _, _),
             let .heartbeat(browser),
             let .browserBlurred(browser, _):
            if client.browser != browser {
                client.browser = browser
                // 同名浏览器只保留最新的那条连接：扩展重连时旧连接会立刻让位，
                // 也让指令投递不再取决于字典的随机顺序（否则冒名者可能截走带绿区 URL 的 navigate）。
                for other in clients.values
                where other !== client && other.browser == browser {
                    drop(other.connection)
                }
            }
            updatePresence()
        }
    }

    private func drop(_ connection: NWConnection) {
        connection.cancel()
        clients[ObjectIdentifier(connection)] = nil
        updatePresence()
    }

    private func startSweepTimer() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 15, repeating: 15)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let now = Date()
            let staleCutoff = now.addingTimeInterval(-Self.staleTimeout)
            let helloCutoff = now.addingTimeInterval(-Self.helloTimeout)
            for client in self.clients.values {
                // 僵尸连接（久无消息），或连上却始终没报出合法 hello 的探测者。
                let isStale = client.lastSeen < staleCutoff
                let neverIdentified = client.browser == nil && client.acceptedAt < helloCutoff
                if isStale || neverIdentified {
                    self.drop(client.connection)
                }
            }
        }
        timer.resume()
        sweepTimer = timer
    }

    private func updatePresence() {
        let present = clients.values.contains { $0.browser != nil }
        if present != hasActiveBrowser {
            hasActiveBrowser = present
            onBrowserPresenceChange?(present)
        }
    }

    private func send(text: String, over connection: NWConnection) {
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "text", metadata: [metadata])
        connection.send(
            content: Data(text.utf8),
            contentContext: context,
            isComplete: true,
            completion: .contentProcessed { _ in }
        )
    }
}

public enum BrowserEvent: Equatable, Sendable {
    case hello(browser: String, version: String)
    case tabActive(browser: String, url: URL, windowId: Int, tabId: Int, timestamp: Date)
    case browserBlurred(browser: String, timestamp: Date)
    case heartbeat(browser: String)
}

public enum BrowserCommand: Equatable, Sendable {
    case navigate(url: URL)
    case frictionOverlay(level: Double)
    case frictionClear
}
