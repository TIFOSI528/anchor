import XCTest
@testable import AnchorDaemon

final class BrowserProtocolTests: XCTestCase {

    // MARK: - decode events

    func testDecodeHello() {
        let event = BrowserProtocol.decodeEvent(#"{"type":"hello","browser":"chrome","version":"1.0.0"}"#)
        XCTAssertEqual(event, .hello(browser: "chrome", version: "1.0.0"))
    }

    func testDecodeTabActive() {
        let line = #"{"type":"tab_active","browser":"chrome","url":"https://twitter.com/home","window_id":1,"tab_id":42,"timestamp":1717545600}"#
        XCTAssertEqual(
            BrowserProtocol.decodeEvent(line),
            .tabActive(
                browser: "chrome",
                url: URL(string: "https://twitter.com/home")!,
                windowId: 1, tabId: 42,
                timestamp: Date(timeIntervalSince1970: 1_717_545_600)
            )
        )
    }

    func testDecodeBrowserBlurred() {
        let line = #"{"type":"browser_blurred","browser":"chrome","timestamp":1717545610}"#
        XCTAssertEqual(
            BrowserProtocol.decodeEvent(line),
            .browserBlurred(browser: "chrome", timestamp: Date(timeIntervalSince1970: 1_717_545_610))
        )
    }

    func testDecodeHeartbeat() {
        XCTAssertEqual(
            BrowserProtocol.decodeEvent(#"{"type":"heartbeat","browser":"chrome"}"#),
            .heartbeat(browser: "chrome")
        )
    }

    // MARK: - backward-compat / robustness

    func testUnknownTypeIsIgnored() {
        XCTAssertNil(BrowserProtocol.decodeEvent(#"{"type":"some_future_event_v2","data":123}"#))
    }

    func testMalformedJSONReturnsNil() {
        XCTAssertNil(BrowserProtocol.decodeEvent("not json at all"))
        XCTAssertNil(BrowserProtocol.decodeEvent(""))
    }

    func testMissingRequiredFieldReturnsNil() {
        // tab_active without url
        XCTAssertNil(BrowserProtocol.decodeEvent(#"{"type":"tab_active","browser":"chrome","window_id":1,"tab_id":2,"timestamp":1}"#))
    }

    // MARK: - encode commands

    func testEncodeNavigateHasTrailingNewlineAndRoundTrips() throws {
        let line = BrowserProtocol.encodeCommand(.navigate(url: URL(string: "https://github.com/x")!))
        XCTAssertTrue(line.hasSuffix("\n"))
        let obj = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
        XCTAssertEqual(obj?["type"] as? String, "navigate")
        XCTAssertEqual(obj?["url"] as? String, "https://github.com/x")
    }

    func testEncodeFrictionOverlay() throws {
        let line = BrowserProtocol.encodeCommand(.frictionOverlay(level: 0.5))
        let obj = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
        XCTAssertEqual(obj?["type"] as? String, "friction_overlay")
        XCTAssertEqual((obj?["level"] as? NSNumber)?.doubleValue, 0.5)
    }

    func testEncodeFrictionClear() throws {
        let line = BrowserProtocol.encodeCommand(.frictionClear)
        let obj = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
        XCTAssertEqual(obj?["type"] as? String, "friction_clear")
    }

    // MARK: - line framing

    func testLineBufferSplitsCompleteLines() {
        var buffer = LineBuffer()
        let lines = buffer.append("a\nb\nc\n")
        XCTAssertEqual(lines, ["a", "b", "c"])
        XCTAssertEqual(buffer.pending, "")
    }

    func testLineBufferHoldsPartialUntilCompleted() {
        var buffer = LineBuffer()
        XCTAssertEqual(buffer.append(#"{"type":"heartb"#), [])
        XCTAssertEqual(buffer.pending, #"{"type":"heartb"#)
        let lines = buffer.append("eat\",\"browser\":\"chrome\"}\n")
        XCTAssertEqual(lines, [#"{"type":"heartbeat","browser":"chrome"}"#])
        XCTAssertEqual(BrowserProtocol.decodeEvent(lines[0]), .heartbeat(browser: "chrome"))
    }
}
