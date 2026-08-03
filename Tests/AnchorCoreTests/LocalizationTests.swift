import XCTest
@testable import AnchorCore

/// 本地化机制的测试。
///
/// 注意这里**测的是机制，不是译文**。单元测试里 `Bundle.main` 是测试运行器，
/// 表查不到 → `L()` 回落到 key。所以：
/// - 能测：回落行为、参数格式化、位置说明符重排、退化输入不崩。
/// - 不能测：某个 key 在某语言下的具体译文（那由 `scripts/build-localizations.py`
///   的 key 对齐 + 说明符一致性校验守住，并接进了 CI）。
final class LocalizationTests: XCTestCase {

    /// 查不到表时必须回落到 key 本身，而不是返回空串或崩掉。
    /// 这条是整套设计的前提：正因为回落是"显示成 key"，界面上才能一眼看出漏翻。
    func testMissingKeyFallsBackToKeyItself() {
        XCTAssertEqual(L("this.key.definitely.does.not.exist"), "this.key.definitely.does.not.exist")
    }

    func testEmptyKeyDoesNotCrash() {
        XCTAssertEqual(L(""), "")
    }

    /// 回落路径上带参数也不能崩——线上真出现漏翻时，格式化必须安全降级。
    func testMissingKeyWithArgumentsDoesNotCrash() {
        let result = L("missing.key.with.args", "x", Int64(3))
        XCTAssertFalse(result.isEmpty)
    }

    /// 位置说明符必须能被重排——这是"译者可以改语序而不用改代码"的依据。
    func testPositionalSpecifiersCanBeReordered() {
        let forward = String(format: "%1$@ then %2$@", locale: .current, "A", "B")
        let reversed = String(format: "%2$@ then %1$@", locale: .current, "A", "B")
        XCTAssertEqual(forward, "A then B")
        XCTAssertEqual(reversed, "B then A")
    }

    /// `%lld` 必须配 `Int64`。全项目的整数参数都按这个约定传，
    /// 传错宽度在某些架构上会读到垃圾值。
    func testInt64FormatsWithLLD() {
        XCTAssertEqual(String(format: "%1$lld", locale: .current, Int64(42)), "42")
        XCTAssertEqual(String(format: "%1$lld 天", locale: .current, Int64(0)), "0 天")
    }

    // MARK: - 生成物的一致性

    /// 仓库里签入的 `.lproj` 必须与 fragments 一致（即有人改了 fragments 但忘了重新生成）。
    /// CI 另有一步跑 `--check`；这条让 `swift test` 也能挡住漏生成。
    func testGeneratedTablesAreInSyncWithFragments() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // AnchorCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repo root
        let localizations = root.appendingPathComponent("Resources/Localizations")
        let fragments = localizations.appendingPathComponent("fragments")

        guard FileManager.default.fileExists(atPath: fragments.path) else {
            throw XCTSkip("fragments 目录不在（打包后的测试环境）")
        }

        // 收集每种语言在 fragments 里的 key，与生成的 .lproj 对比。
        var fragmentKeys: [String: Set<String>] = [:]
        let files = try FileManager.default.contentsOfDirectory(at: fragments, includingPropertiesForKeys: nil)
        for file in files where file.pathExtension == "strings" {
            let parts = file.lastPathComponent.split(separator: ".")
            guard parts.count == 3 else { continue }
            let lang = String(parts[1])
            fragmentKeys[lang, default: []].formUnion(Self.keys(in: file))
        }

        XCTAssertFalse(fragmentKeys.isEmpty, "没有找到任何 fragment")

        for (lang, expected) in fragmentKeys {
            let generated = localizations
                .appendingPathComponent("\(lang).lproj/Localizable.strings")
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: generated.path),
                "\(lang) 缺少生成的 Localizable.strings——请运行 scripts/build-localizations.py"
            )
            let actual = Self.keys(in: generated)
            XCTAssertEqual(
                actual, expected,
                "\(lang) 的生成表与 fragments 不一致（改了 fragments 忘了重新生成？）"
                + " 缺：\(expected.subtracting(actual).sorted().prefix(5))"
                + " 多：\(actual.subtracting(expected).sorted().prefix(5))"
            )
        }
    }

    /// 每种语言的 key 集合必须完全一致——少一条就会在界面上显示成裸 key。
    func testAllLanguagesDefineTheSameKeys() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let localizations = root.appendingPathComponent("Resources/Localizations")
        guard FileManager.default.fileExists(atPath: localizations.path) else {
            throw XCTSkip("Resources/Localizations 不在（打包后的测试环境）")
        }
        let lprojs = try FileManager.default
            .contentsOfDirectory(at: localizations, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "lproj" }
        guard lprojs.count > 1 else { throw XCTSkip("只有一种语言，无需比对") }

        var perLanguage: [String: Set<String>] = [:]
        for lproj in lprojs {
            let name = lproj.deletingPathExtension().lastPathComponent
            perLanguage[name] = Self.keys(in: lproj.appendingPathComponent("Localizable.strings"))
        }
        guard let reference = perLanguage["en"] else {
            return XCTFail("缺少 en.lproj 作为参考")
        }
        for (lang, keys) in perLanguage where lang != "en" {
            XCTAssertEqual(keys, reference, "\(lang) 与 en 的 key 集合不一致")
        }
    }

    private static func keys(in file: URL) -> Set<String> {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return [] }
        var result: Set<String> = []
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("\""), let end = trimmed.dropFirst().firstIndex(of: "\"") else { continue }
            result.insert(String(trimmed[trimmed.index(after: trimmed.startIndex)..<end]))
        }
        return result
    }
}
