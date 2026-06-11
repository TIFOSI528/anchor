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

    public typealias EventHandler = @Sendable (BrowserEvent) -> Void

    /// `@unchecked Sendable`：仅在 `queue` 上读写。
    private final class Client: @unchecked Sendable {
        let connection: NWConnection
        var browser: String?
        var lastSeen = Date()
        init(connection: NWConnection) { self.connection = connection }
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
            guard let self,
                  let client = self.clients.values.first(where: { $0.browser == browser }) else { return }
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
            if let data, let text = String(data: data, encoding: .utf8) {
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
            let cutoff = Date().addingTimeInterval(-Self.staleTimeout)
            for client in self.clients.values where client.lastSeen < cutoff {
                self.drop(client.connection)
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
