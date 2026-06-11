import XCTest
@testable import AnchorCore

final class PresetEngineTests: XCTestCase {

    let engine = PresetEngine()

    // MARK: - basic classification

    func testGreenAppMatches() {
        let preset = Preset(
            id: "test",
            name: "Test",
            greenRules: [.app(bundleId: "com.apple.dt.Xcode")]
        )
        let ctx = AppContext(bundleId: "com.apple.dt.Xcode")
        XCTAssertEqual(engine.classify(ctx, in: preset), .green)
    }

    func testRedTakesPriorityOverGreen() {
        // Twitter feed must be red even though twitter.com/* would otherwise be in green.
        let preset = Preset(
            id: "test",
            name: "Test",
            greenRules: [.url(pattern: "twitter.com/*")],
            redRules: [.url(pattern: "twitter.com/home")]
        )
        let ctx = AppContext(
            bundleId: "com.apple.Safari",
            url: URL(string: "https://twitter.com/home")
        )
        XCTAssertEqual(engine.classify(ctx, in: preset), .red)
    }

    func testUnclassifiedFallsToGray() {
        let preset = Preset(id: "test", name: "Test")
        let ctx = AppContext(bundleId: "com.unknown.app")
        XCTAssertEqual(engine.classify(ctx, in: preset), .gray)
    }

    // MARK: - URL wildcard

    func testWildcardMatchesSubpath() {
        let preset = Preset(
            id: "test",
            name: "Test",
            greenRules: [.url(pattern: "github.com/myorg/*")]
        )
        let ctx = AppContext(
            bundleId: "com.google.Chrome",
            url: URL(string: "https://github.com/myorg/anchor/issues/1")
        )
        XCTAssertEqual(engine.classify(ctx, in: preset), .green)
    }

    func testWildcardDoesNotOverMatch() {
        let preset = Preset(
            id: "test",
            name: "Test",
            greenRules: [.url(pattern: "github.com/myorg/*")]
        )
        let ctx = AppContext(
            bundleId: "com.google.Chrome",
            url: URL(string: "https://github.com/otherorg/repo")
        )
        XCTAssertEqual(engine.classify(ctx, in: preset), .gray)
    }

    // MARK: - builtin presets

    func testBuiltinWriteCodeAllowsVSCode() {
        let ctx = AppContext(bundleId: "com.microsoft.VSCode")
        XCTAssertEqual(engine.classify(ctx, in: BuiltinPresets.writeCode), .green)
    }

    func testBuiltinWriteCodeBlocksTwitterHome() {
        let ctx = AppContext(
            bundleId: "com.google.Chrome",
            url: URL(string: "https://twitter.com/home")
        )
        XCTAssertEqual(engine.classify(ctx, in: BuiltinPresets.writeCode), .red)
    }
}
