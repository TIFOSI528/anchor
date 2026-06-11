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
