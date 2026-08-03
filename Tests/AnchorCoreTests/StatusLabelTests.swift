import XCTest
@testable import AnchorCore

/// 状态文案现在走 `L()`。单元测试里 `Bundle.main` 是 test runner，查不到 `.lproj`，
/// 所以 `L("status.green")` 回落到 **key 本身**——这里就对 key 断言。
///
/// 这比原来对"绿区"断言更好：断言不再跟某一种语言绑定，改译文不会弄红测试，
/// 而把 key 拼错、或某个分支忘了本地化，仍然会被抓住。
/// 时钟格式（`m:ss`）在 `L()` 里会被 `String(format:)` 丢掉，所以直接测 `clock`。
final class StatusLabelTests: XCTestCase {

    private let app = AppContext(bundleId: "com.example.app")

    func testGreenLabel() {
        XCTAssertEqual(StatusLabel.text(for: .green(currentApp: app)), "status.green")
    }

    func testRedLabel() {
        XCTAssertEqual(StatusLabel.text(for: .red(currentApp: app)), "status.red")
    }

    func testOfflineLabel() {
        XCTAssertEqual(StatusLabel.text(for: .offline), "status.offline")
    }

    func testPausedLabel() {
        XCTAssertEqual(StatusLabel.text(for: .paused(reason: "lunch")), "status.paused")
    }

    func testDriftingUsesItsOwnKey() {
        XCTAssertEqual(StatusLabel.text(for: .drifting(elapsed: 30, currentApp: app)), "status.drifting")
        XCTAssertEqual(StatusLabel.text(for: .drifting(elapsed: 90, currentApp: app)), "status.drifting")
        XCTAssertEqual(StatusLabel.text(for: .drifting(elapsed: 0, currentApp: app)), "status.drifting")
    }

    func testSlackingUsesItsOwnKey() {
        XCTAssertEqual(StatusLabel.text(for: .slacking(remaining: 300)), "status.slacking")
        XCTAssertNotEqual(StatusLabel.text(for: .slacking(remaining: 300)),
                          StatusLabel.text(for: .drifting(elapsed: 300, currentApp: app)))
    }

    func testClockFormatsAsMinutesSeconds() {
        XCTAssertEqual(StatusLabel.clock(30), "0:30")
        XCTAssertEqual(StatusLabel.clock(90), "1:30")
        XCTAssertEqual(StatusLabel.clock(0), "0:00")
        XCTAssertEqual(StatusLabel.clock(300), "5:00")
        XCTAssertEqual(StatusLabel.clock(5), "0:05")
    }

    func testNegativeElapsedClampsToZero() {
        XCTAssertEqual(StatusLabel.clock(-10), "0:00")
        XCTAssertEqual(StatusLabel.text(for: .drifting(elapsed: -10, currentApp: app)), "status.drifting")
    }

    /// 真实表下的完整输出。原来断言的 "漂移 0:30" / "摸鱼 5:00" 一条没少，
    /// 只是现在**显式指定语言**，而且英文一起验——顺带证明 `%1$@` 位置说明符写对了。
    func testRealTableEmbedsTheClockInBothLanguages() throws {
        try LocalizedTable.withLanguage("zh-Hans") {
            XCTAssertEqual(StatusLabel.text(for: .green(currentApp: app)), "绿区")
            XCTAssertEqual(StatusLabel.text(for: .red(currentApp: app)), "红区")
            XCTAssertEqual(StatusLabel.text(for: .offline), "待命")
            XCTAssertEqual(StatusLabel.text(for: .paused(reason: "lunch")), "已暂停")
            XCTAssertEqual(StatusLabel.text(for: .drifting(elapsed: 30, currentApp: app)), "漂移 0:30")
            XCTAssertEqual(StatusLabel.text(for: .drifting(elapsed: 90, currentApp: app)), "漂移 1:30")
            XCTAssertEqual(StatusLabel.text(for: .drifting(elapsed: -10, currentApp: app)), "漂移 0:00")
            XCTAssertEqual(StatusLabel.text(for: .slacking(remaining: 300)), "摸鱼 5:00")
            XCTAssertEqual(StatusLabel.text(for: .slacking(remaining: 5)), "摸鱼 0:05")
        }
        try LocalizedTable.withLanguage("en") {
            XCTAssertEqual(StatusLabel.text(for: .drifting(elapsed: 90, currentApp: app)), "Drifting 1:30")
            XCTAssertEqual(StatusLabel.text(for: .slacking(remaining: 5)), "Slacking 0:05")
            XCTAssertEqual(StatusLabel.text(for: .offline), "Standing by")
        }
    }

    /// 每个状态一个 key，不许两个状态共用一条文案。
    func testEveryStateHasADistinctKey() {
        let keys = [
            StatusLabel.text(for: .green(currentApp: app)),
            StatusLabel.text(for: .drifting(elapsed: 1, currentApp: app)),
            StatusLabel.text(for: .red(currentApp: app)),
            StatusLabel.text(for: .slacking(remaining: 1)),
            StatusLabel.text(for: .paused(reason: "x")),
            StatusLabel.text(for: .offline)
        ]
        XCTAssertEqual(Set(keys).count, keys.count)
    }
}
