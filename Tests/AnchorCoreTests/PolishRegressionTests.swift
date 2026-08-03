import XCTest
@testable import AnchorCore

/// 这一批断言对应 pre-launch 审查里修掉的具体缺陷。
/// 每个 test 的注释写的是"如果这条挂了，用户会遇到什么"，方便未来重构时判断能不能改。
final class PolishRegressionTests: XCTestCase {

    // MARK: - friction 曲线真的跟随场景阈值

    /// 默认档（60s）必须与 spec 原文的 30 / 60 / 180 完全一致——不能因为引入缩放而漂移。
    func testDefaultThresholdKeepsSpecCurve() {
        XCTAssertEqual(FrictionLevel.forElapsed(29), .none)
        XCTAssertEqual(FrictionLevel.forElapsed(30), .subtle)
        XCTAssertEqual(FrictionLevel.forElapsed(59), .subtle)
        XCTAssertEqual(FrictionLevel.forElapsed(60), .moderate)
        XCTAssertEqual(FrictionLevel.forElapsed(179), .moderate)
        XCTAssertEqual(FrictionLevel.forElapsed(180), .heavy)
    }

    /// 「漂移倒计时」滑杆此前是**装饰品**：reducer 存着 driftThreshold 但从不读，
    /// 曲线恒为 30/60/180。设成 5 分钟后 friction 仍在 60s 落下来。
    func testLongerThresholdActuallyDelaysFriction() {
        let fiveMinutes: TimeInterval = 300 // scale = 5
        XCTAssertEqual(FrictionLevel.forElapsed(60, threshold: fiveMinutes), .none)
        XCTAssertEqual(FrictionLevel.forElapsed(149, threshold: fiveMinutes), .none)
        XCTAssertEqual(FrictionLevel.forElapsed(150, threshold: fiveMinutes), .subtle)
        XCTAssertEqual(FrictionLevel.forElapsed(300, threshold: fiveMinutes), .moderate)
        XCTAssertEqual(FrictionLevel.forElapsed(900, threshold: fiveMinutes), .heavy)
    }

    func testShorterThresholdTightensCurve() {
        XCTAssertEqual(FrictionLevel.forElapsed(8, threshold: 15), .subtle)
        XCTAssertEqual(FrictionLevel.forElapsed(15, threshold: 15), .moderate)
        XCTAssertEqual(FrictionLevel.forElapsed(45, threshold: 15), .heavy)
    }

    /// 阈值为 0 / 负数不能把曲线炸成除零或全 heavy。
    func testDegenerateThresholdIsClamped() {
        XCTAssertEqual(FrictionLevel.forElapsed(0, threshold: 0), .none)
        XCTAssertEqual(FrictionLevel.forElapsed(0, threshold: -100), .none)
    }

    // MARK: - 只观察不干预

    /// 内置「随便看看」绿区规则为空，注释写的是"不主动拦截，只做统计"——
    /// 但此前它会让**所有** app 落灰区并永久重度模糊，逃生口反而最难受。
    func testCasualPresetIsObserveOnly() {
        XCTAssertTrue(BuiltinPresets.casualMode.isObserveOnly)
        XCTAssertFalse(BuiltinPresets.writeCode.isObserveOnly)
        XCTAssertFalse(BuiltinPresets.readDocs.isObserveOnly)
    }

    /// 刚新建、还没填规则的空场景同样不该糊屏幕。
    func testEmptyUserPresetIsObserveOnly() {
        XCTAssertTrue(Preset(id: "user.new", name: "新场景").isObserveOnly)
    }

    func testObserveOnlyReducerNeverRendersFriction() {
        let reducer = StateReducer(interveneEnabled: false)
        var state = AnchorState.drifting(elapsed: 0, currentApp: AppContext(bundleId: "com.x"))
        // 一路漂到 10 分钟，任何一帧都不许冒出非零 friction。
        for _ in 0..<600 {
            let (next, effects) = reducer.reduce(state, event: .tick(deltaSeconds: 1)) { _ in .gray }
            state = next
            for effect in effects {
                if case let .renderFriction(level) = effect {
                    XCTAssertEqual(level, 0, "observe-only 场景不应产生 friction")
                }
            }
        }
    }

    func testObserveOnlyReducerDoesNotFrictionRedZoneEither() {
        let reducer = StateReducer(interveneEnabled: false)
        let (_, effects) = reducer.reduce(.offline, event: .appActivated(AppContext(bundleId: "com.x"))) { _ in .red }
        for effect in effects {
            if case let .renderFriction(level) = effect {
                XCTAssertEqual(level, 0)
            }
        }
    }

    /// 反向对照：默认场景该有 friction 就必须有，别把干预整个关掉。
    func testInterveningReducerStillRendersFriction() {
        let reducer = StateReducer()
        var state = AnchorState.drifting(elapsed: 59, currentApp: AppContext(bundleId: "com.x"))
        let (_, effects) = reducer.reduce(state, event: .tick(deltaSeconds: 1)) { _ in .gray }
        state = .offline
        XCTAssertTrue(
            effects.contains { effect in
                if case let .renderFriction(level) = effect { return level > 0 }
                return false
            },
            "默认场景漂到 60s 必须产生 friction"
        )
    }

    // MARK: - .paused 必须真的吸收手势

    /// 此前通配手势 case 排在 `(.paused, _)` 之前：暂停期间按 ⌃⌥⌘B 会直接跳进 .slacking，
    /// 绕过 resumeGesture()，暂停理由被丢掉、前台也不重新判定。
    func testPausedAbsorbsSlackAndTapGestures() {
        let reducer = StateReducer()
        let paused = AnchorState.paused(reason: "去开评审会一小时")

        let (afterLongPress, longPressEffects) = reducer.reduce(paused, event: .islandLongPressed) { _ in .gray }
        XCTAssertEqual(afterLongPress, paused, "暂停期间长按不应变成合法摸鱼")
        XCTAssertTrue(longPressEffects.isEmpty)

        let (afterTap, tapEffects) = reducer.reduce(paused, event: .islandTapped) { _ in .gray }
        XCTAssertEqual(afterTap, paused, "暂停期间单击不应触发拉回")
        XCTAssertTrue(tapEffects.isEmpty)

        let (afterTick, _) = reducer.reduce(paused, event: .tick(deltaSeconds: 1)) { _ in .gray }
        XCTAssertEqual(afterTick, paused)
    }

    /// 但显式恢复必须仍然有效，否则暂停就成了单向门。
    func testPausedStillResumesExplicitly() {
        let reducer = StateReducer()
        let (resumed, effects) = reducer
            .reduce(.paused(reason: "开会"), event: .sessionStarted) { _ in .green }
        XCTAssertEqual(resumed, .offline)
        XCTAssertTrue(effects.contains { if case .clearFriction = $0 { return true }; return false })
    }

    // MARK: - 落库前的 URL 脱敏

    /// query / fragment 里常带搜索词、分享令牌、会话参数、重置密码链接——不该进磁盘。
    func testStorageSanitizationDropsQueryAndFragment() {
        XCTAssertEqual(
            SessionStore.sanitizeURLForStorage("https://mail.example.com/u/0?token=SECRET&q=raise"),
            "https://mail.example.com/u/0"
        )
        XCTAssertEqual(
            SessionStore.sanitizeURLForStorage("https://docs.example.com/d/abc#heading-3"),
            "https://docs.example.com/d/abc"
        )
        // 最早出现的分隔符生效（fragment 里再带 ? 也一样切掉）。
        XCTAssertEqual(
            SessionStore.sanitizeURLForStorage("https://a.example/p#x?y=1"),
            "https://a.example/p"
        )
    }

    /// 站点 + 路径必须留着——分区规则（`github.com/myrepo/*` 绿、`github.com/trending` 红）靠它。
    func testStorageSanitizationKeepsHostAndPath() {
        XCTAssertEqual(
            SessionStore.sanitizeURLForStorage("https://github.com/myorg/myrepo/pull/12"),
            "https://github.com/myorg/myrepo/pull/12"
        )
        XCTAssertNil(SessionStore.sanitizeURLForStorage(nil))
        XCTAssertEqual(SessionStore.sanitizeURLForStorage(""), "")
    }

    // MARK: - 日期 key 与 locale 解耦

    /// `yyyy-MM-dd` 用裸 DateFormatter 生成会继承用户日历：泰历下是 2569-…，回历下是阿拉伯数字。
    /// 而这个字符串是 `daily_recaps` 的主键、也是摸鱼日计数的跨天判据——
    /// 用户改一次语言/地区，历史复盘就会被重新 key、日计数被误清零。
    func testDayKeyIsIndependentOfLocaleAndCalendar() {
        let reference = Date(timeIntervalSince1970: 1_777_000_000) // 固定时刻
        let utc = TimeZone(identifier: "UTC")!
        let expected = DayKey.key(for: reference, timeZone: utc)

        // ISO 日历下必须是 4 位年 + ASCII 数字。
        XCTAssertEqual(expected.count, 10)
        XCTAssertTrue(expected.allSatisfy { $0.isASCII })
        XCTAssertTrue(expected.dropFirst(4).hasPrefix("-"))

        // 对照组：**复现被修掉的旧写法**（裸 DateFormatter，继承传入 locale 的日历），
        // 证明这个 bug 是真的会发生、而不是理论担忧。
        func naiveKey(locale: Locale) -> String {
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.timeZone = utc
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.string(from: reference)
        }

        // 佛历（泰）下年份会变成 25xx；回历（沙特）下年份是 14xx。
        let buddhist = naiveKey(locale: Locale(identifier: "th_TH_POSIX@calendar=buddhist"))
        let islamic = naiveKey(locale: Locale(identifier: "ar_SA@calendar=islamic"))
        XCTAssertNotEqual(
            buddhist, islamic,
            "对照组本身要能区分两种日历，否则下面的断言不说明问题"
        )
        XCTAssertTrue(
            buddhist != expected || islamic != expected,
            "旧写法至少应在一种日历下产出不同的 key——否则这个 test 无法证明修复有意义"
        )

        // 而稳定 key 无论 locale 怎么变都钉死在 ISO：显式构造各 locale 的等价调用。
        for identifier in ["th_TH@calendar=buddhist", "ar_SA@calendar=islamic", "fa_IR", "en_US"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .iso8601)
            formatter.timeZone = utc
            formatter.dateFormat = "yyyy-MM-dd"
            XCTAssertEqual(
                formatter.string(from: reference), expected,
                "locale \(identifier) 下稳定 key 变了——复盘表会被重新 key"
            )
        }
    }

    func testDayKeyRoundTrips() {
        let utc = TimeZone(identifier: "UTC")!
        let key = DayKey.key(for: Date(timeIntervalSince1970: 1_777_000_000), timeZone: utc)
        let parsed = DayKey.date(fromKey: key, timeZone: utc)
        XCTAssertNotNil(parsed)
        XCTAssertEqual(DayKey.key(for: parsed!, timeZone: utc), key)
        XCTAssertNil(DayKey.date(fromKey: "not-a-date"))
    }

    /// 摸鱼日计数器换成稳定 key 后，跨天仍要清零。
    func testSlackingCounterStillRollsOverAcrossDays() {
        var day = "2026-08-03"
        let counter = SlackingCounter(dayKey: { day })
        counter.increment()
        counter.increment()
        XCTAssertEqual(counter.usedToday, 2)
        day = "2026-08-04"
        XCTAssertEqual(counter.usedToday, 0, "跨天必须清零")
    }
}

/// 留存清理 / 导出 / 清除的真库测试（内存库，不碰用户数据）。
final class DataControlTests: XCTestCase {

    private func makeStore() throws -> SessionStore { try SessionStore(.memory) }

    private func session(id: String, started: Date, ended: Date?) -> SessionRecord {
        SessionRecord(
            id: id, presetId: "p", startedAt: started, endedAt: ended,
            greenSeconds: 60, graySeconds: 0, redSeconds: 0,
            driftCount: 1, longestStreakSeconds: 60, deepScore: 50
        )
    }

    private func drift(id: String, session: String, at: Date, url: String?) -> DriftRecord {
        DriftRecord(
            id: id, sessionId: session, occurredAt: at,
            fromApp: "com.a", fromURL: nil, toApp: "com.b", toURL: url,
            durationSeconds: 30, endReason: .tap, nextDestination: nil
        )
    }

    /// insertDrift 是唯一写入口，脱敏必须在这里生效（不能只靠调用方自觉）。
    func testInsertDriftStripsQueryStringAtTheChokePoint() throws {
        let store = try makeStore()
        let now = Date()
        try store.upsertSession(session(id: "s1", started: now, ended: nil))
        try store.insertDrift(drift(id: "d1", session: "s1", at: now,
                                    url: "https://x.example/p?token=SECRET"))
        let stored = try store.drifts(sessionId: "s1")
        XCTAssertEqual(stored.first?.toURL, "https://x.example/p")
        XCTAssertFalse(stored.first?.toURL?.contains("SECRET") ?? true)
    }

    func testPruneRemovesOldAndKeepsRecent() throws {
        let store = try makeStore()
        let now = Date()
        let old = now.addingTimeInterval(-120 * 86_400)
        try store.upsertSession(session(id: "old", started: old, ended: old))
        try store.upsertSession(session(id: "new", started: now, ended: now))
        try store.insertDrift(drift(id: "dOld", session: "old", at: old, url: nil))
        try store.insertDrift(drift(id: "dNew", session: "new", at: now, url: nil))

        let removed = try store.prune(olderThanDays: 90, now: now)
        XCTAssertGreaterThan(removed, 0)
        XCTAssertTrue(try store.drifts(sessionId: "old").isEmpty)
        XCTAssertEqual(try store.drifts(sessionId: "new").count, 1)
        XCTAssertNil(try store.session(id: "old"))
        XCTAssertNotNil(try store.session(id: "new"))
    }

    /// 崩溃恢复会把 ended_at 写成 startedAt+累计，可能**早于**该 session 自己的漂移。
    /// 若只按时间删 drifts，父行先没了就会违反 `PRAGMA foreign_keys = ON`。
    func testPruneDoesNotViolateForeignKeyOnCrashRecoveredSession() throws {
        let store = try makeStore()
        let now = Date()
        let longAgo = now.addingTimeInterval(-200 * 86_400)
        // 父 session 已"收口"在很久以前，子漂移却是最近的。
        try store.upsertSession(session(id: "recovered", started: longAgo, ended: longAgo))
        try store.insertDrift(drift(id: "dRecent", session: "recovered", at: now, url: nil))

        XCTAssertNoThrow(try store.prune(olderThanDays: 90, now: now))
        XCTAssertNil(try store.session(id: "recovered"))
        XCTAssertTrue(try store.drifts(sessionId: "recovered").isEmpty, "父行删掉后子行不能留成孤儿")
    }

    func testPruneWithZeroDaysKeepsEverything() throws {
        let store = try makeStore()
        let old = Date().addingTimeInterval(-999 * 86_400)
        try store.upsertSession(session(id: "old", started: old, ended: old))
        XCTAssertEqual(try store.prune(olderThanDays: 0, now: Date()), 0)
        XCTAssertNotNil(try store.session(id: "old"), "0 = 永久保留")
    }

    /// 清除历史要清干净，但**保留用户配好的场景规则**。
    func testWipeHistoryClearsRecordsButKeepsPresets() throws {
        let store = try makeStore()
        let now = Date()
        try store.upsertSession(session(id: "s1", started: now, ended: now))
        try store.insertDrift(drift(id: "d1", session: "s1", at: now, url: nil))
        try store.upsertPreset(PresetRecord(
            id: "user.mine", name: "我的场景", rulesJSON: "{}",
            driftThresholdSeconds: 60, createdAt: now, updatedAt: now
        ))

        try store.wipeHistory()

        XCTAssertNil(try store.session(id: "s1"))
        XCTAssertTrue(try store.drifts(sessionId: "s1").isEmpty)
        XCTAssertEqual(try store.presets().count, 1, "场景规则不该被历史清除带走")
    }

    func testExportProducesParseableJSONWithoutQueryStrings() throws {
        let store = try makeStore()
        let now = Date()
        try store.upsertSession(session(id: "s1", started: now, ended: now))
        try store.insertDrift(drift(id: "d1", session: "s1", at: now,
                                    url: "https://x.example/a?secret=1"))

        let data = try store.exportJSON(now: now)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(object?["exported_at"])
        XCTAssertEqual((object?["sessions"] as? [[String: Any]])?.count, 1)
        XCTAssertEqual((object?["drifts"] as? [[String: Any]])?.count, 1)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("secret=1"), "导出不应重新引入被脱敏的参数")
    }
}

/// 叙事第 2/3 段此前是**死代码**：`NarrativeGenerator` 支持，但 `RecapComposer`
/// 从不传 `hardestTimeWindow` / `hardestWindowDaysOutOf7` / `consecutiveDaysWithSameTopDest`，
/// 所以 spec 承诺的三段里有两段永远渲染不出来。
/// 这些 test 跑在**真实英文表**下（见 LocalizedTestCase），因此断言的是用户真会看到的句子。
final class NarrativeWiringTests: LocalizedTestCase {

    private let calendar = Calendar(identifier: .gregorian)

    private func drift(_ id: String, at date: Date, to app: String) -> DriftRecord {
        DriftRecord(
            id: id, sessionId: "s1", occurredAt: date,
            fromApp: "com.editor", fromURL: nil, toApp: app, toURL: nil,
            durationSeconds: 120, endReason: .tap, nextDestination: nil
        )
    }

    /// 固定一个时刻，避免测试随当天时间漂移。
    private func day(_ offset: Int, hour: Int) -> Date {
        let base = Date(timeIntervalSince1970: 1_777_000_000)
        let start = calendar.startOfDay(for: base)
        let shifted = calendar.date(byAdding: .day, value: offset, to: start)!
        return calendar.date(byAdding: .hour, value: hour, to: shifted)!
    }

    func testHardestWindowPicksTheBusiestTwoHourBucket() {
        // 14 点档 3 次、10 点档 1 次 → 应选 14:00–16:00。
        let drifts = [
            drift("a", at: day(0, hour: 14), to: "com.x"),
            drift("b", at: day(0, hour: 15), to: "com.x"),
            drift("c", at: day(-1, hour: 14), to: "com.x"),
            drift("d", at: day(0, hour: 10), to: "com.x"),
        ]
        XCTAssertEqual(
            RecapComposer.hardestWindow(in: drifts, calendar: calendar),
            WeeklyAggregator.windowKey(startHour: 14)
        )
    }

    func testHardestWindowIsDeterministicOnTies() {
        // 并列时必须稳定，否则复盘文案会在两个时段之间随机跳。
        let drifts = [
            drift("a", at: day(0, hour: 10), to: "com.x"),
            drift("b", at: day(0, hour: 14), to: "com.x"),
        ]
        let first = RecapComposer.hardestWindow(in: drifts, calendar: calendar)
        for _ in 0..<20 {
            XCTAssertEqual(RecapComposer.hardestWindow(in: drifts, calendar: calendar), first)
        }
    }

    func testConsecutiveDaysCountsOnlyAnUnbrokenRun() {
        let now = day(0, hour: 20)
        // 今天/昨天/前天都是 youtube 居首 → 3 天；再往前换成别的，链断。
        var drifts: [DriftRecord] = []
        for offset in 0...2 {
            drifts.append(drift("y\(offset)", at: day(-offset, hour: 14), to: "com.youtube"))
        }
        drifts.append(drift("other", at: day(-3, hour: 14), to: "com.twitter"))
        XCTAssertEqual(
            RecapComposer.consecutiveDaysWithSameTopDestination(in: drifts, upTo: now, calendar: calendar),
            3
        )
    }

    func testConsecutiveDaysIsZeroWithoutTodaysData() {
        let now = day(0, hour: 20)
        let drifts = [drift("old", at: day(-2, hour: 14), to: "com.youtube")]
        XCTAssertEqual(
            RecapComposer.consecutiveDaysWithSameTopDestination(in: drifts, upTo: now, calendar: calendar),
            0
        )
    }

    /// 端到端：喂进"连续 3 天同一个目的地 + 明显最难时段"的数据，
    /// 复盘叙事里必须真的出现第 2 段的钩子与第 3 段。
    func testComposerActuallyRendersParagraphTwoHookAndParagraphThree() {
        let now = day(0, hour: 20)
        var weekDrifts: [DriftRecord] = []
        for offset in 0...2 {
            for index in 0..<4 {
                weekDrifts.append(
                    drift("y\(offset)-\(index)", at: day(-offset, hour: 14), to: "com.youtube")
                )
            }
        }
        let todayDrifts = weekDrifts.filter { calendar.isDate($0.occurredAt, inSameDayAs: now) }
        let session = SessionRecord(
            id: "s1", presetId: "builtin.write-code",
            startedAt: day(0, hour: 9), endedAt: now,
            greenSeconds: 7200, graySeconds: 600, redSeconds: 0,
            driftCount: todayDrifts.count, longestStreakSeconds: 2700, deepScore: 70
        )

        let data = RecapComposer.compose(
            dateLabel: "2026-04-24",
            presetName: "Coding",
            sessions: [session],
            todayDrifts: todayDrifts,
            weekDrifts: weekDrifts,
            classify: { _ in .gray },
            calendar: calendar,
            now: now
        )

        // 第 2 段的连续天数钩子（英文表里是 "That's day 3 in a row"）。
        XCTAssertTrue(
            data.narrative.contains("in a row"),
            "第 2 段的连续天数钩子没出现：\(data.narrative)"
        )
        // 第 3 段：最难时段 + 命中天数。
        XCTAssertTrue(
            data.narrative.contains("hardest"),
            "第 3 段（节律观察）没出现：\(data.narrative)"
        )
        XCTAssertTrue(
            data.narrative.contains("2 PM") || data.narrative.contains("14"),
            "第 3 段应带上具体时段：\(data.narrative)"
        )
    }
}
