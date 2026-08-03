import Foundation
import XCTest
@testable import AnchorCore

/// 让测试用**仓库里签入的真实本地化表**跑断言。
///
/// 默认情况下单测里 `Bundle.main` 是测试运行器，查不到表 → `L()` 回落到 key，
/// 且参数会被丢掉。那样一来"叙事有没有正确带上 47 分钟"就无法验证。
/// 指向 `Resources/Localizations` 之后：
/// - 断言跑在真实英文输出上；
/// - 表里的位置说明符写错（比如 `%1$@` 写成 `%@`）也会被这些断言抓到。
enum LocalizedTable {

    static let repositoryRoot: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // AnchorCoreTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // repo root

    /// 以 `Resources/Localizations` 为 bundle 根——里面就是 `en.lproj` / `zh-Hans.lproj`，
    /// `Bundle.localizedString` 会按传入的语言偏好在其中挑一个。
    static var bundle: Bundle? {
        Bundle(url: repositoryRoot.appendingPathComponent("Resources/Localizations"))
    }

    /// 在指定语言下运行一段断言。结束后恢复原状，避免测试间互相污染。
    static func withLanguage<T>(_ language: String, _ body: () throws -> T) throws -> T {
        guard let bundle else {
            throw XCTSkip("找不到 Resources/Localizations（打包后的测试环境）")
        }
        // Bundle 的语言选择跟 AppleLanguages 走；直接指到具体的 .lproj 更确定。
        let lproj = repositoryRoot
            .appendingPathComponent("Resources/Localizations/\(language).lproj")
        let languageBundle = Bundle(url: lproj) ?? bundle

        let previous = localizationBundleOverride
        localizationBundleOverride = languageBundle
        defer { localizationBundleOverride = previous }
        return try body()
    }
}

/// 需要真实译文的测试统一继承这个基类：整个 case 都跑在英文表下。
class LocalizedTestCase: XCTestCase {

    private var previous: Bundle?

    override func setUpWithError() throws {
        try super.setUpWithError()
        let lproj = LocalizedTable.repositoryRoot
            .appendingPathComponent("Resources/Localizations/en.lproj")
        guard let bundle = Bundle(url: lproj) else {
            throw XCTSkip("找不到 en.lproj（打包后的测试环境）")
        }
        previous = localizationBundleOverride
        localizationBundleOverride = bundle
    }

    override func tearDown() {
        localizationBundleOverride = previous
        previous = nil
        super.tearDown()
    }
}
