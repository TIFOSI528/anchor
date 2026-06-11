import XCTest
@testable import AnchorCore

final class FocusLockTests: XCTestCase {

    private let engine = PresetEngine()
    private let preset = BuiltinPresets.writeCode // 绿含 VSCode/github.com/*，红含 x.com/home

    private func ctx(_ bundleId: String, _ url: String? = nil) -> AppContext {
        AppContext(bundleId: bundleId, url: url.flatMap(URL.init(string:)))
    }

    // MARK: - page lock（用户关心的核心：站内乱逛也算漂移）

    func testPageLockAllowsThatPageAndSubpaths() {
        let lock = FocusLock.page(for: URL(string: "https://blog.example.com/2026/06/deep-post")!, bundleId: "b")!
        XCTAssertTrue(lock.allows(ctx("com.google.Chrome", "https://blog.example.com/2026/06/deep-post")))
        // 锚点 / 查询参数不破锁（匹配只看 host+path）
        XCTAssertTrue(lock.allows(ctx("com.google.Chrome", "https://blog.example.com/2026/06/deep-post?from=rss#part2")))
    }

    func testPageLockBlocksSameSiteOtherPages() {
        let lock = FocusLock.page(for: URL(string: "https://blog.example.com/2026/06/deep-post")!, bundleId: "b")!
        XCTAssertFalse(lock.allows(ctx("com.google.Chrome", "https://blog.example.com/")))
        XCTAssertFalse(lock.allows(ctx("com.google.Chrome", "https://blog.example.com/2026/07/other-post")))
    }

    func testRootPathPageLockDegradesToSiteLock() {
        let lock = FocusLock.page(for: URL(string: "https://blog.example.com/")!, bundleId: "b")!
        XCTAssertEqual(lock.target, .urlPrefix(pattern: "blog.example.com/*"))
    }

    // MARK: - site lock

    func testSiteLockAllowsWholeHostOnly() {
        let lock = FocusLock.site(for: URL(string: "https://arxiv.org/abs/2406.01234")!, bundleId: "b")!
        XCTAssertTrue(lock.allows(ctx("com.google.Chrome", "https://arxiv.org/pdf/2406.01234")))
        XCTAssertFalse(lock.allows(ctx("com.google.Chrome", "https://news.ycombinator.com/")))
    }

    // MARK: - app lock

    func testAppLockMatchesBundleIdRegardlessOfURL() {
        let lock = FocusLock.app(bundleId: "com.apple.Preview", name: "预览")
        XCTAssertTrue(lock.allows(ctx("com.apple.Preview")))
        XCTAssertFalse(lock.allows(ctx("com.apple.Safari")))
    }

    // MARK: - classify：锁 > 红 > 灰

    func testLockedTargetIsGreen() {
        let lock = FocusLock.site(for: URL(string: "https://blog.example.com/x")!, bundleId: "b")!
        let zone = lock.classify(ctx("com.google.Chrome", "https://blog.example.com/y"), preset: preset, engine: engine)
        XCTAssertEqual(zone, .green)
    }

    func testPresetGreenIsSuppressedToGrayUnderLock() {
        let lock = FocusLock.app(bundleId: "com.apple.Preview", name: "预览")
        // VSCode 平时是绿区，锁定期间压成灰
        XCTAssertEqual(lock.classify(ctx("com.microsoft.VSCode"), preset: preset, engine: engine), .gray)
        XCTAssertEqual(lock.classify(ctx("com.google.Chrome", "https://github.com/x/y"), preset: preset, engine: engine), .gray)
    }

    func testPresetRedStaysRedUnderLock() {
        let lock = FocusLock.app(bundleId: "com.apple.Preview", name: "预览")
        XCTAssertEqual(lock.classify(ctx("com.google.Chrome", "https://x.com/home"), preset: preset, engine: engine), .red)
    }

    func testLockWinsOverRedForLockedTarget() {
        // 明确锁到一个平时在红名单的页面：用户声明的意图最大
        let lock = FocusLock.page(for: URL(string: "https://x.com/home")!, bundleId: "b")!
        XCTAssertEqual(lock.classify(ctx("com.google.Chrome", "https://x.com/home"), preset: preset, engine: engine), .green)
    }
}
