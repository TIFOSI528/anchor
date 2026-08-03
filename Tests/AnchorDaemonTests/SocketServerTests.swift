import XCTest
@testable import AnchorDaemon

/// 真连接集成测试：起一个 ephemeral 端口的 WS server，用 URLSessionWebSocketTask 连上去。
final class SocketServerTests: XCTestCase {

    private var server: SocketServer?

    override func tearDown() {
        server?.stop()
        server = nil
        super.tearDown()
    }

    private func startServer(handler: @escaping @Sendable (BrowserEvent) -> Void) throws -> UInt16 {
        let server = SocketServer(port: 0, handler: handler)
        self.server = server
        try server.start()
        // listener ready 是异步的，轮询拿端口（最多 2s）。
        for _ in 0..<200 {
            if let port = server.boundPort { return port }
            Thread.sleep(forTimeInterval: 0.01)
        }
        throw XCTSkip("WS listener did not become ready (sandboxed environment?)")
    }

    private func connect(port: UInt16) -> URLSessionWebSocketTask {
        let task = URLSession.shared.webSocketTask(with: URL(string: "ws://127.0.0.1:\(port)")!)
        task.resume()
        return task
    }

    private final class EventBox: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [BrowserEvent] = []
        func append(_ event: BrowserEvent) { lock.lock(); items.append(event); lock.unlock() }
        var all: [BrowserEvent] { lock.lock(); defer { lock.unlock() }; return items }
    }

    func testHelloEventArrivesAtHandler() throws {
        let received = expectation(description: "hello received")
        let box = EventBox()
        let port = try startServer { event in
            box.append(event)
            if case .hello = event { received.fulfill() }
        }

        let task = connect(port: port)
        task.send(.string(#"{"type":"hello","browser":"chrome","version":"1.0.0"}"#)) { error in
            XCTAssertNil(error)
        }

        wait(for: [received], timeout: 5)
        XCTAssertEqual(box.all.first, .hello(browser: "chrome", version: "1.0.0"))
        task.cancel(with: .normalClosure, reason: nil)
    }

    func testCommandIsDeliveredToRegisteredBrowser() throws {
        let helloSeen = expectation(description: "hello registered")
        let port = try startServer { event in
            if case .hello = event { helloSeen.fulfill() }
        }

        let task = connect(port: port)
        let commandReceived = expectation(description: "command received")
        task.receive { result in
            if case let .success(.string(text)) = result {
                XCTAssertTrue(text.contains("\"navigate\""))
                XCTAssertTrue(text.contains("github.com"))
                commandReceived.fulfill()
            } else {
                XCTFail("expected text message, got \(result)")
            }
        }

        task.send(.string(#"{"type":"hello","browser":"chrome","version":"1.0.0"}"#)) { _ in }
        wait(for: [helloSeen], timeout: 5)

        server?.send(command: .navigate(url: URL(string: "https://github.com/x")!), to: "chrome")
        wait(for: [commandReceived], timeout: 5)
        task.cancel(with: .normalClosure, reason: nil)
    }

    func testUnknownAndMalformedMessagesAreIgnoredWithoutCrash() throws {
        let heartbeat = expectation(description: "valid event still processed afterwards")
        let port = try startServer { event in
            if case .heartbeat = event { heartbeat.fulfill() }
        }

        let task = connect(port: port)
        task.send(.string("not json")) { _ in }
        task.send(.string(#"{"type":"future_v9","x":1}"#)) { _ in }
        task.send(.string(#"{"type":"heartbeat","browser":"chrome"}"#)) { _ in }

        wait(for: [heartbeat], timeout: 5)
        task.cancel(with: .normalClosure, reason: nil)
    }

    // MARK: - Origin 准入（挡住"任意网页连本机 socket"）

    /// 网页来源必须被拒：Chrome 把 127.0.0.1 当可信来源，所以任何 https 页面都能发起连接。
    func testWebPageOriginsAreRejected() {
        XCTAssertFalse(SocketServer.isAcceptableOrigin("https://evil.example"))
        XCTAssertFalse(SocketServer.isAcceptableOrigin("http://localhost:3000"))
        XCTAssertFalse(SocketServer.isAcceptableOrigin("https://github.com"))
        // sandbox iframe 的不透明来源，同样不是我们的扩展。
        XCTAssertFalse(SocketServer.isAcceptableOrigin("null"))
        // 大小写/空白不该成为绕过手段。
        XCTAssertFalse(SocketServer.isAcceptableOrigin("  HTTPS://Evil.Example  "))
    }

    /// 扩展来源与"根本没有 Origin 头"都必须放行——否则会把产品核心功能整个打死。
    func testExtensionAndHeaderlessOriginsAreAccepted() {
        XCTAssertTrue(SocketServer.isAcceptableOrigin("chrome-extension://abcdefghijklmnop"))
        XCTAssertTrue(SocketServer.isAcceptableOrigin("moz-extension://some-uuid"))
        XCTAssertTrue(SocketServer.isAcceptableOrigin("safari-web-extension://x"))
        XCTAssertTrue(SocketServer.isAcceptableOrigin(nil))
        XCTAssertTrue(SocketServer.isAcceptableOrigin(""))
    }

    /// 端到端：带网页 Origin 的握手连不上，且**连上后也拿不到任何事件**
    /// （即攻击者无法伪造 tab_active 来污染漂移库或消掉 friction）。
    func testWebPageOriginCannotDeliverEventsEndToEnd() throws {
        let box = EventBox()
        let port = try startServer { box.append($0) }

        var request = URLRequest(url: URL(string: "ws://127.0.0.1:\(port)")!)
        request.setValue("https://evil.example", forHTTPHeaderField: "Origin")
        let task = URLSession.shared.webSocketTask(with: request)
        task.resume()
        task.send(.string(#"{"type":"tab_active","browser":"chrome","url":"https://green.example/","window_id":1,"tab_id":1,"timestamp":1}"#)) { _ in }

        // 给握手 + 消息一个宽裕的窗口，然后断言什么都没进来。
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertTrue(
            box.all.isEmpty,
            "网页来源的连接不应能投递任何事件，却收到了 \(box.all)"
        )
        task.cancel(with: .normalClosure, reason: nil)

        // 对照组：同一台 server、同一条消息，只是不带 Origin 头——必须能投递成功。
        // 没有这一步，上面的断言可能只是"消息压根没发出去"的假阳性。
        let control = connect(port: port)
        control.send(.string(#"{"type":"tab_active","browser":"chrome","url":"https://green.example/","window_id":1,"tab_id":1,"timestamp":1}"#)) { _ in }
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertFalse(
            box.all.isEmpty,
            "对照组（无 Origin 头）本应投递成功——否则上面的拒绝断言不成立"
        )
        control.cancel(with: .normalClosure, reason: nil)
    }

    func testPresenceCallbackFiresOnHello() throws {
        let present = expectation(description: "presence true")
        let server = SocketServer(port: 0) { _ in }
        self.server = server
        server.onBrowserPresenceChange = { isPresent in
            if isPresent { present.fulfill() }
        }
        try server.start()
        var port: UInt16?
        for _ in 0..<200 {
            if let p = server.boundPort { port = p; break }
            Thread.sleep(forTimeInterval: 0.01)
        }
        let boundPort = try XCTUnwrap(port)

        let task = connect(port: boundPort)
        task.send(.string(#"{"type":"hello","browser":"chrome","version":"1.0.0"}"#)) { _ in }
        wait(for: [present], timeout: 5)
        task.cancel(with: .normalClosure, reason: nil)
    }
}
