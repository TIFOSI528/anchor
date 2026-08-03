import Foundation

/// 哨兵值：`localizedString(forKey:value:table:)` 查不到时会原样返回传入的 `value`，
/// 用一个不可能作为译文出现的串来区分"查不到"与"译文恰好等于 key"。
private let missingMarker = "\u{0}__anchor_missing__"

/// 本地化查表入口。
///
/// **为什么不用 `Bundle.module`**：SwiftPM 会给每个 target 生成独立资源 bundle，
/// 而 SwiftUI 的 `Text("字面量")`（以及 Toggle / Button / Section 的字面量，它们本身
/// 就是 `LocalizedStringKey`）默认查 **`Bundle.main`**。两者对不上时的表现是
/// "翻译全做了、界面还是原语言"，且没有任何报错。
///
/// **为什么不用 `.xcstrings`**：实测（Swift 6.2 / Xcode 26）SwiftPM 没有 String Catalog
/// 的编译规则，只会把 `.xcstrings` 原样拷进 bundle，查表返回 key 本身——同样静默失败。
///
/// 所以：`.lproj/Localizable.strings` 放在 `Resources/Localizations/`（`Sources/` 之外，
/// 不参与 SwiftPM 资源打包），由 `scripts/package-app.sh` 拷进 `Contents/Resources/`。
/// 这样 `Bundle.main` 就是 app bundle，AnchorCore 与 AnchorApp 共用同一张表。
///
/// `swift run` / 单元测试下 `Bundle.main` 不是 app bundle，查不到表会**回落到 key**。
/// 这是刻意的：测试因此可以对 key 断言（稳定、与语言无关），而不是对某种语言的译文断言。
/// 仅供测试注入一张真实的本地化表。
///
/// 生产代码从不设置它，永远走 `Bundle.main`。
/// 之所以需要这个缝：回落路径下 `L("key", args)` 会把参数**丢掉**（key 里没有说明符），
/// 于是"叙事里有没有正确带上 47 分钟"这类断言在测试里根本无从验证。
/// 让测试指向仓库里签入的 `Resources/Localizations`，就能对**真实英文输出**断言，
/// 顺带把表里的说明符是否写对也一起验证了。
package nonisolated(unsafe) var localizationBundleOverride: Bundle?

public func L(_ key: String) -> String {
    let bundle = localizationBundleOverride ?? .main
    let value = bundle.localizedString(forKey: key, value: missingMarker, table: nil)
    return value == missingMarker ? key : value
}

/// 带参数的版本。参数位置由 `.strings` 里的 `%1$@` / `%2$lld` 决定——
/// 译者可以为不同语序重排位置而不必改代码。
public func L(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: L(key), locale: .current, arguments: arguments)
}

/// 复数形式（走 `.stringsdict`）。中文没有复数变化，但英 / 德 / 俄 / 阿有，
/// 所以「3 次」这类文案必须交给系统的复数规则，不能靠拼接。
public func LPlural(_ key: String, _ count: Int) -> String {
    String(format: L(key), locale: .current, count)
}
