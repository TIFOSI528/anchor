import XCTest
@testable import AnchorCore

final class PresetCaptureTests: XCTestCase {

    private var preset: Preset {
        Preset(
            id: "p", name: "测试",
            greenRules: [.app(bundleId: "green.app"), .url(pattern: "github.com/*")],
            redRules: [.app(bundleId: "red.app"), .url(pattern: "x.com/home")]
        )
    }

    func testCaptureGreenAppendsAppRule() {
        let result = preset.capturing(bundleId: "new.app", as: .green)
        XCTAssertTrue(result.greenRules.contains(.app(bundleId: "new.app")))
        XCTAssertFalse(result.redRules.contains(.app(bundleId: "new.app")))
    }

    func testCaptureRedRemovesFromGreen() {
        // 互斥：绿区 app 拉进红区，自动移出绿区
        let result = preset.capturing(bundleId: "green.app", as: .red)
        XCTAssertFalse(result.greenRules.contains(.app(bundleId: "green.app")))
        XCTAssertTrue(result.redRules.contains(.app(bundleId: "green.app")))
    }

    func testCaptureGreenRemovesFromRed() {
        let result = preset.capturing(bundleId: "red.app", as: .green)
        XCTAssertTrue(result.greenRules.contains(.app(bundleId: "red.app")))
        XCTAssertFalse(result.redRules.contains(.app(bundleId: "red.app")))
    }

    func testCaptureGrayRemovesFromBoth() {
        let result = preset.capturing(bundleId: "green.app", as: .gray)
        XCTAssertFalse(result.greenRules.contains(.app(bundleId: "green.app")))
        XCTAssertFalse(result.redRules.contains(.app(bundleId: "green.app")))
    }

    func testCaptureIsIdempotentNoDuplicates() {
        let result = preset
            .capturing(bundleId: "new.app", as: .red)
            .capturing(bundleId: "new.app", as: .red)
        XCTAssertEqual(result.redRules.filter { $0 == .app(bundleId: "new.app") }.count, 1)
    }

    func testURLRulesUntouched() {
        let result = preset.capturing(bundleId: "green.app", as: .red)
        XCTAssertTrue(result.greenRules.contains(.url(pattern: "github.com/*")))
        XCTAssertTrue(result.redRules.contains(.url(pattern: "x.com/home")))
    }

    // MARK: - url capture

    func testCaptureURLPatternMutuallyExclusive() {
        let result = preset.capturing(urlPattern: "github.com/*", as: .red)
        XCTAssertFalse(result.greenRules.contains(.url(pattern: "github.com/*")))
        XCTAssertTrue(result.redRules.contains(.url(pattern: "github.com/*")))
        // app 规则不受影响
        XCTAssertTrue(result.greenRules.contains(.app(bundleId: "green.app")))
    }

    func testCaptureURLGrayRemovesPattern() {
        let result = preset.capturing(urlPattern: "x.com/home", as: .gray)
        XCTAssertNil(result.membership(ofURLPattern: "x.com/home"))
    }

    func testCaptureURLOnlyExactPatternAffected() {
        let result = preset.capturing(urlPattern: "x.com/*", as: .green)
        // 既有的 x.com/home 红规则保持不动（互斥只对完全相同的 pattern）
        XCTAssertEqual(result.membership(ofURLPattern: "x.com/home"), .red)
        XCTAssertEqual(result.membership(ofURLPattern: "x.com/*"), .green)
    }

    // MARK: - membership

    func testMembershipQueries() {
        XCTAssertEqual(preset.membership(ofApp: "green.app"), .green)
        XCTAssertEqual(preset.membership(ofApp: "red.app"), .red)
        XCTAssertNil(preset.membership(ofApp: "unknown.app"))
        XCTAssertEqual(preset.membership(ofURLPattern: "github.com/*"), .green)
        XCTAssertNil(preset.membership(ofURLPattern: "github.com"))
    }
}
