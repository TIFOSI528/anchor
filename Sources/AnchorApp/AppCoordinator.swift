import AppKit
import AnchorCore
import AnchorDaemon

/// 总装 coordinator：NSWorkspace + Daemon + StateReducer + 持久化 + 灵动岛 + Friction。
///
/// 单一信息源：`state` 是唯一状态，UI（菜单栏 / 灵动岛）都订阅它。
@MainActor
final class AppCoordinator {

    var onStateChange: ((AnchorState) -> Void)?

    // MARK: - core

    private var reducer = StateReducer()
    private let presetEngine = PresetEngine()
    private let monitor = AppMonitor()
    private let tabRegistry = BrowserTabRegistry()
    private let lastGreen = LastGreenAppTracker()
    private let slackingPolicy = SlackingPolicy()
    private let slackingCounter = SlackingCounter()

    private(set) var state: AnchorState = .offline {
        didSet {
            onStateChange?(state)
            renderIsland()
        }
    }

    // MARK: - persistence

    private let writeQueue = DispatchQueue(label: "com.anchor.session-writer", qos: .utility)
    private var store: SessionStore?
    private var sessionId = UUID().uuidString
    private var sessionStartedAt = Date()
    private var accumulator = SessionAccumulator()
    private var driftLogger: DriftLogger?
    private(set) var presetLibrary: PresetLibrary!

    // MARK: - UI / effects

    let island = IslandController()
    private let fog = FrictionFogController()
    private let inputFriction = InputFriction()
    private let hotkeys = HotkeyMonitor()
    private var recapWindow: RecapWindowController?

    // MARK: - timers & transient state

    private var workspaceObserver: NSObjectProtocol?
    private var tickTimer: Timer?
    private var checkpointTimer: Timer?
    private var recapTimer: Timer?
    private var weeklyTimer: Timer?
    private var redBuffer: DispatchWorkItem?
    private var redEnteredAt: Date?
    private var pendingReturnReason: DriftRecord.EndReason?
    private var currentSlackMode: SlackingPolicy.Mode = .soft

    private lazy var daemon = SocketServer { [weak self] event in
        DispatchQueue.main.async {
            MainActor.assumeIsolated { self?.handleBrowserEvent(event) }
        }
    }

    private var defaults: UserDefaults { .standard }

    // MARK: - lifecycle

    func start() {
        store = try? SessionStore()
        presetLibrary = PresetLibrary(store: store, writeQueue: writeQueue)
        presetLibrary.onActivePresetChange = { [weak self] preset in
            self?.rebuildReducer(for: preset)
        }

        configureUICallbacks()
        recoverCrashedSessionIfAny()
        openSession()

        // rebuildReducer 内部会对当前前台 app 立即重判（此时 session/日志器已就绪）。
        rebuildReducer(for: presetLibrary.activePreset)

        observeFrontmostApp()
        startDaemon()
        hotkeys.start()
        scheduleRecapTimers()
        startCheckpointTimer()

        onStateChange?(state)
    }

    func stop() {
        if let observer = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            workspaceObserver = nil
        }
        hotkeys.stop()
        tickTimer?.invalidate()
        checkpointTimer?.invalidate()
        recapTimer?.invalidate()
        weeklyTimer?.invalidate()
        redBuffer?.cancel()
        closeSession()
        daemon.stop()
        fog.clear()
        inputFriction.update(level: 0)
    }

    // MARK: - capture（一键收编）

    /// 收编对象：浏览器且已知 tab → 站点（url pattern）；否则整个 app。
    struct CaptureTarget {
        enum Mode {
            case app(bundleId: String)
            case site(pattern: String)
        }
        let mode: Mode
        let name: String
        /// 当前已在哪个名单（nil = 灰区兜底）——菜单据此打钩/置灰。
        let membership: ZoneClassification?
        /// true = 前台是浏览器但拿不到 tab（扩展未连），收编会作用于整个应用。
        let isWholeBrowserApp: Bool
    }

    /// 取最近一次记录的前台上下文（AppMonitor 本就排除 Anchor 自己——
    /// 点状态栏菜单时 frontmostApplication 可能短暂变成 Anchor，monitor.current 不受影响）。
    var captureTarget: CaptureTarget? {
        guard let ctx = monitor.current else { return nil }
        let preset = presetLibrary.activePreset
        if let host = ctx.url?.host {
            let pattern = host + "/*"
            return CaptureTarget(
                mode: .site(pattern: pattern),
                name: host,
                membership: preset.membership(ofURLPattern: pattern),
                isWholeBrowserApp: false
            )
        }
        return CaptureTarget(
            mode: .app(bundleId: ctx.bundleId),
            name: displayName(for: ctx),
            membership: preset.membership(ofApp: ctx.bundleId),
            isWholeBrowserApp: tabRegistry.browserName(forBundleId: ctx.bundleId) != nil
        )
    }

    /// 收编进绿/红区（互斥），`.gray` = 移回灰区；变更后立即对前台 app 重新判定。
    func captureCurrent(as zone: ZoneClassification) {
        guard let target = captureTarget else {
            island.flashHint("当前没有可收编的对象")
            return
        }
        switch target.mode {
        case .app(let bundleId):
            presetLibrary.capture(bundleId: bundleId, as: zone)
        case .site(let pattern):
            presetLibrary.captureURL(pattern: pattern, as: zone)
        }
        // capture → upsert → onActivePresetChange → rebuildReducer → reclassifyFrontmost
        switch zone {
        case .green: island.flashHint("已加入绿区：\(target.name)")
        case .red: island.flashHint("已加入红区：\(target.name)")
        case .gray: island.flashHint("已移回灰区：\(target.name)")
        }
    }

    /// 规则变更后对当前前台 app 立刻重新分类（绕过 AppMonitor 去重）。
    private func reclassifyFrontmost() {
        var bundleId = monitor.current?.bundleId
        if bundleId == nil {
            let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            if frontmost != Bundle.main.bundleIdentifier { bundleId = frontmost }
        }
        guard let bundleId else { return }
        monitor.reset()
        handleFrontmostChange(bundleId: bundleId)
    }

    // MARK: - Focus Lock（"只看这个"）

    private(set) var focusLock: FocusLock?

    /// 菜单可选的锁定目标（按当前上下文显隐：有 tab → 页/站；否则 app）。
    struct LockCandidates {
        var page: FocusLock?
        var site: FocusLock?
        var app: (lock: FocusLock, isWholeBrowserApp: Bool)?
    }

    var lockCandidates: LockCandidates? {
        guard let ctx = monitor.current else { return nil }
        var candidates = LockCandidates()
        if let url = ctx.url {
            candidates.page = FocusLock.page(for: url, bundleId: ctx.bundleId)
            candidates.site = FocusLock.site(for: url, bundleId: ctx.bundleId)
        } else {
            candidates.app = (
                lock: FocusLock.app(bundleId: ctx.bundleId, name: displayName(for: ctx)),
                isWholeBrowserApp: tabRegistry.browserName(forBundleId: ctx.bundleId) != nil
            )
        }
        return candidates
    }

    func engageLock(_ lock: FocusLock) {
        focusLock = lock
        island.model.locked = true
        island.flashHint("已锁定：\(lock.label)")
        reclassifyFrontmost()
    }

    func disengageLock() {
        guard focusLock != nil else { return }
        focusLock = nil
        island.model.locked = false
        island.flashHint("已解除锁定")
        reclassifyFrontmost()
    }

    /// ⌥⌘L：未锁 → 锁到最具体目标（页 > app）；已锁 → 解锁。
    func toggleLockHotkey() {
        if focusLock != nil {
            disengageLock()
        } else if let candidates = lockCandidates,
                  let lock = candidates.page ?? candidates.app?.lock {
            engageLock(lock)
        } else {
            island.flashHint("当前没有可锁定的对象")
        }
    }

    // MARK: - gestures (menu / hotkey / island 共用入口)

    func snapBackGesture() {
        pendingReturnReason = .tap
        handleEvent(.islandTapped)
    }

    func slackGesture() {
        let used = slackingCounter.usedToday
        currentSlackMode = slackingPolicy.mode(usedToday: used)
        slackingCounter.increment()
        handleEvent(.islandLongPressed)
        island.flashHint(currentSlackMode == .hard
            ? "今天第 \(used + 1) 次摸鱼（已到硬上限，到点强制拉回）"
            : "合法摸鱼 5 分钟（今天第 \(used + 1) 次）")
    }

    func pauseGesture() {
        guard let reason = PauseReasonPrompt.ask() else { return }
        handleEvent(.islandSwipedUp(reason: reason))
    }

    // MARK: - recap

    func openRecapWindow() {
        composeRecap { [weak self] data in
            guard let self else { return }
            if let record = data.map(self.recapRecord(from:)) {
                let store = self.store
                self.writeQueue.async { try? store?.upsertDailyRecap(record) }
            }
            if self.recapWindow == nil {
                self.recapWindow = RecapWindowController(data: data)
            }
            self.recapWindow?.show(data: data)
        }
    }

    // MARK: - workspace & browser events

    private func observeFrontmostApp() {
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let bundleId = app.bundleIdentifier else { return }
            MainActor.assumeIsolated {
                self?.handleFrontmostChange(bundleId: bundleId)
            }
        }
    }

    private func handleFrontmostChange(bundleId: String) {
        guard bundleId != Bundle.main.bundleIdentifier else { return } // 自己的窗口不参与判定
        let ctx = tabRegistry.enrich(AppContext(bundleId: bundleId))
        guard let event = monitor.record(bundleId: ctx.bundleId, url: ctx.url, at: Date()) else { return }
        handleEvent(event)
    }

    private func handleBrowserEvent(_ event: BrowserEvent) {
        switch event {
        case let .tabActive(browser, url, _, _, _):
            tabRegistry.recordActiveTab(browser: browser, url: url)
            // 只有该浏览器在前台时，tab 变化才驱动状态机（PR #19 合并规则）。
            if let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
               tabRegistry.bundleIds(for: browser).contains(frontmost) {
                handleFrontmostChange(bundleId: frontmost)
            }
        case let .browserBlurred(browser, _):
            tabRegistry.clear(browser: browser)
        case .hello, .heartbeat:
            break
        }
    }

    private func startDaemon() {
        daemon.onBrowserPresenceChange = { present in
            DispatchQueue.main.async {
                UserDefaults.standard.set(present, forKey: SettingsKey.extensionConnected)
            }
        }
        do {
            try daemon.start()
        } catch {
            NSLog("[Anchor] daemon failed to start: \(error)")
        }
    }

    // MARK: - state pipeline

    private func handleEvent(_ event: AnchorEvent) {
        let preset = presetLibrary.activePreset
        let lock = focusLock
        let (next, effects) = reducer.reduce(state, event: event) { [presetEngine] ctx in
            // Focus Lock 是 classifier overlay：锁 > 红 > 灰（见 FocusLock.classify）。
            if let lock { return lock.classify(ctx, preset: preset, engine: presetEngine) }
            return presetEngine.classify(ctx, in: preset)
        }
        bookkeep(from: state, to: next, event: event)
        state = next
        apply(effects)
        manageTickTimer()
    }

    /// 状态迁移时的记账：时间累计、漂移日志、绿区栈、红区缓冲。
    private func bookkeep(from old: AnchorState, to new: AnchorState, event: AnchorEvent) {
        let now = Date()
        accumulator.transition(to: zone(of: new), at: now)

        if case let .green(ctx) = new {
            lastGreen.record(ctx)
            if let closed = driftLogger?.returnToGreen(at: now, reason: pendingReturnReason ?? .autoReturn) {
                insert(closed)
            }
            pendingReturnReason = nil
        }

        if let ctx = nonGreenContext(of: new), zone(of: new) != .green {
            if let closed = driftLogger?.enterNonGreen(from: greenContext(of: old), to: ctx, at: now) {
                insert(closed)
            }
        }

        switch (isRed(old), isRed(new)) {
        case (false, true): redEnteredAt = now
        case (true, false): redEnteredAt = nil; redBuffer?.cancel()
        default: break
        }

        // 软上限摸鱼到点：问"还要 5 分钟吗？"
        if case .slacking = old, case .offline = new, currentSlackMode == .soft {
            askForSlackExtension()
        }
    }

    private func apply(_ effects: [SideEffect]) {
        for effect in effects {
            switch effect {
            case .snapBackToGreen:
                performSnapBack()
            case .renderFriction(let level):
                renderFriction(level: level)
            case .clearFriction:
                redBuffer?.cancel()
                fog.clear()
                inputFriction.update(level: 0)
                daemon.broadcast(command: .frictionClear)
            case .playHaptic(let type):
                playHaptic(type)
            case .writeLog(let entry):
                NSLog("[Anchor] log: \(entry.to.bundleId)")
            case .sendNotification(let message):
                island.flashHint(message)
            case .showRecap:
                openRecapWindow()
            }
        }
    }

    /// 红区 friction 留 5 秒缓冲（dynamic-island-spec §二：手滑切错要能无痛切回）。
    private func renderFriction(level: Double) {
        redBuffer?.cancel()
        guard isRed(state) else {
            applyFriction(level: level)
            return
        }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.isRed(self.state) else { return }
                self.applyFriction(level: level)
            }
        }
        redBuffer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
    }

    private func applyFriction(level: Double) {
        fog.render(level: level)
        inputFriction.update(level: level)
        if level >= FrictionLevel.heavy.blurIntensity {
            daemon.broadcast(command: .frictionOverlay(level: level))
        }
    }

    private func performSnapBack() {
        guard let target = lastGreen.snapBackTarget else {
            island.flashHint("暂无可拉回的目标，请先访问绿区 app")
            return
        }
        if let url = target.url,
           let browser = tabRegistry.browserName(forBundleId: target.bundleId) {
            daemon.send(command: .navigate(url: url), to: browser)
        }
        NSWorkspace.shared.runningApplications
            .first { $0.bundleIdentifier == target.bundleId }?
            .activate()
    }

    private func playHaptic(_ type: HapticType) {
        guard defaults.object(forKey: SettingsKey.hapticsEnabled) == nil
            || defaults.bool(forKey: SettingsKey.hapticsEnabled) else { return }
        let pattern: NSHapticFeedbackManager.FeedbackPattern
        switch type {
        case .alignment: pattern = .alignment
        case .levelChange: pattern = .levelChange
        case .generic: pattern = .generic
        }
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .default)
    }

    private func askForSlackExtension() {
        let alert = NSAlert()
        alert.messageText = "5 分钟到了"
        alert.informativeText = "还要 5 分钟吗？（今天剩余软上限 \(max(0, 3 - slackingCounter.usedToday)) 次）"
        alert.addButton(withTitle: "回去工作")
        alert.addButton(withTitle: "再来 5 分钟")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertSecondButtonReturn {
            slackGesture()
        }
    }

    // MARK: - tick driver（绿区/离线不跑任何定时器——不变量 1）

    private func manageTickTimer() {
        let needsTicks: Bool
        switch state {
        case .drifting, .red, .slacking: needsTicks = true
        case .green, .paused, .offline: needsTicks = false
        }
        if needsTicks, tickTimer == nil {
            tickTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
        } else if !needsTicks {
            tickTimer?.invalidate()
            tickTimer = nil
        }
    }

    private func tick() {
        if isRed(state) {
            renderIsland() // 红区 elapsed 由 redEnteredAt 推，reducer 不变
        }
        handleEvent(.tick(deltaSeconds: 1))
    }

    private func renderIsland() {
        let redElapsed = redEnteredAt.map { Int(Date().timeIntervalSince($0)) } ?? 0
        island.render(
            state: state,
            redElapsed: redElapsed,
            driftThreshold: Int(presetLibrary?.activePreset.driftThresholdSeconds ?? 60),
            snapBackName: lastGreen.snapBackTarget.map(displayName(for:))
        )
    }

    private func displayName(for ctx: AppContext) -> String {
        NSWorkspace.shared.runningApplications
            .first { $0.bundleIdentifier == ctx.bundleId }?.localizedName ?? ctx.destinationLabel
    }

    // MARK: - session persistence (PR #23)

    private func openSession() {
        sessionId = UUID().uuidString
        sessionStartedAt = Date()
        accumulator = SessionAccumulator()
        driftLogger = DriftLogger(sessionId: sessionId)
        persistSession(endedAt: nil)
    }

    private func closeSession() {
        let now = Date()
        if let closed = driftLogger?.sessionEnded(at: now) {
            insert(closed)
        }
        accumulator.transition(to: nil, at: now)
        persistSession(endedAt: now)
    }

    /// app crash 后把上次"进行中 session"按已累计的数据收口（CrashSafety）。
    private func recoverCrashedSessionIfAny() {
        guard let store else { return }
        writeQueue.async {
            guard var stale = (try? store.inProgressSession()) ?? nil else { return }
            let accumulated = stale.greenSeconds + stale.graySeconds + stale.redSeconds
            stale.endedAt = stale.startedAt.addingTimeInterval(TimeInterval(max(accumulated, 1)))
            try? store.upsertSession(stale)
        }
    }

    private func persistSession(endedAt: Date?) {
        guard let store else { return }
        let totals = accumulator.snapshot(at: Date())
        let score = DeepScore().compute(input: .init(
            greenMinutes: Double(totals.greenSeconds) / 60,
            grayMinutes: Double(totals.graySeconds) / 60,
            redMinutes: Double(totals.redSeconds) / 60,
            driftCount: totals.driftCount
        ))
        let record = SessionRecord(
            id: sessionId,
            presetId: presetLibrary?.activePresetId ?? "",
            startedAt: sessionStartedAt,
            endedAt: endedAt,
            greenSeconds: totals.greenSeconds,
            graySeconds: totals.graySeconds,
            redSeconds: totals.redSeconds,
            driftCount: totals.driftCount,
            longestStreakSeconds: totals.longestStreakSeconds,
            deepScore: score
        )
        writeQueue.async { try? store.upsertSession(record) }
    }

    private func insert(_ drift: DriftRecord) {
        guard let store else { return }
        writeQueue.async { try? store.insertDrift(drift) }
    }

    /// 每 60s 一次的 crash-safety checkpoint（轻量异步写，数据安全优先于"零后台工作"）。
    private func startCheckpointTimer() {
        checkpointTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if case .offline = self.state { return }
                self.persistSession(endedAt: nil)
            }
        }
    }

    // MARK: - recap & weekly scheduling

    private func scheduleRecapTimers() {
        let nextRecap = RecapScheduler.nextDaily(hour: 22, after: Date())
        recapTimer = Timer(fire: nextRecap, interval: 86_400, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.island.flashHint("今日复盘好了，点菜单栏查看")
                self?.openRecapWindow()
            }
        }
        RunLoop.main.add(recapTimer!, forMode: .common)

        let nextWeekly = RecapScheduler.nextWeekly(weekday: 1, hour: 21, after: Date())
        weeklyTimer = Timer(fire: nextWeekly, interval: 7 * 86_400, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.runWeeklySuggestion() }
        }
        RunLoop.main.add(weeklyTimer!, forMode: .common)
    }

    private func composeRecap(_ completion: @escaping @MainActor (RecapData?) -> Void) {
        guard let store else { completion(nil); return }
        persistSession(endedAt: nil) // 让进行中数据进库
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: Date())
        let weekStart = calendar.date(byAdding: .day, value: -6, to: dayStart) ?? dayStart
        let presetName = presetLibrary.activePreset.name
        let preset = presetLibrary.activePreset
        let engine = presetEngine

        writeQueue.async {
            // 队列上只做 I/O；组装挪到主线程——displayName 解析要用 NSWorkspace。
            let sessions = (try? store.sessions(from: dayStart, to: Date().addingTimeInterval(60))) ?? []
            let todayDrifts = (try? store.drifts(from: dayStart, to: Date().addingTimeInterval(60))) ?? []
            let weekDrifts = (try? store.drifts(from: weekStart, to: Date().addingTimeInterval(60))) ?? []

            Task { @MainActor in
                guard !(sessions.isEmpty && todayDrifts.isEmpty) else {
                    completion(nil)
                    return
                }
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                let data = RecapComposer.compose(
                    dateLabel: formatter.string(from: Date()),
                    presetName: presetName,
                    sessions: sessions,
                    todayDrifts: todayDrifts,
                    weekDrifts: weekDrifts,
                    seriousMode: UserDefaults.standard.bool(forKey: SettingsKey.seriousMode),
                    classify: { drift in
                        let ctx = AppContext(bundleId: drift.toApp, url: drift.toURL.flatMap(URL.init(string:)))
                        return engine.classify(ctx, in: preset) == .red ? .red : .gray
                    },
                    displayName: { AppIconProvider.friendly($0) }
                )
                completion(data)
            }
        }
    }

    private func recapRecord(from data: RecapData) -> DailyRecapRecord {
        DailyRecapRecord(
            date: data.dateLabel,
            deepScore: data.deepScore,
            narrative: data.narrative,
            generatedAt: Date()
        )
    }

    private func runWeeklySuggestion() {
        guard let store else { return }
        let calendar = Calendar.current
        let weekStart = calendar.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let preset = presetLibrary.activePreset
        let presetName = preset.name

        writeQueue.async { [weak self] in
            let drifts = (try? store.drifts(from: weekStart, to: Date())) ?? []
            let greenAppIds = Set(preset.greenRules.compactMap { rule -> String? in
                if case let .app(bundleId) = rule { return bundleId }
                return nil
            })
            let input = WeeklyAggregator.weeklyInput(
                presetName: presetName,
                drifts: drifts,
                isGreenSource: { greenAppIds.contains($0) }
            )
            guard let suggestion = SuggestionEngine.weeklySuggestion(input) else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.present(suggestion) }
            }
        }
    }

    /// 每周一条、可解释、可一键 apply（daily-recap-spec §六）。
    private func present(_ suggestion: Suggestion) {
        let alert = NSAlert()
        alert.messageText = "本周建议"
        alert.informativeText = "\(suggestion.message)\n\n依据：\(suggestion.rationale)"
        alert.addButton(withTitle: "应用")
        alert.addButton(withTitle: "这周先不用")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        switch suggestion.kind {
        case .blacklist:
            let rule = inferRule(for: suggestion.target)
            presetLibrary.appendRedRule(rule)
            saveRevertInfo(kind: "blacklist", line: PresetSerialization.line(for: rule))
        case .presetAdjust:
            let rule = ZoneRule.app(bundleId: suggestion.target)
            presetLibrary.removeGreenRule(rule)
            saveRevertInfo(kind: "presetAdjust", line: PresetSerialization.line(for: rule))
        case .rhythm:
            island.flashHint("可在设置里给 \(suggestion.target) 启用更严格的场景")
        }
    }

    /// target 可能是 URL host（"x.com"）或 bundle id（"com.x.app"）：
    /// 本机装了同名 bundle 的按 app 规则，否则按 url 通配。
    private func inferRule(for target: String) -> ZoneRule {
        if NSWorkspace.shared.urlForApplication(withBundleIdentifier: target) != nil {
            return .app(bundleId: target)
        }
        return .url(pattern: target + "/*")
    }

    private func saveRevertInfo(kind: String, line: String) {
        defaults.set(
            ["kind": kind, "line": line, "presetId": presetLibrary.activePresetId,
             "appliedAt": Date().timeIntervalSince1970] as [String: Any],
            forKey: SettingsKey.lastSuggestion
        )
    }

    /// Settings 里"撤销上次建议"（apply 后一周内有效）。
    func revertLastSuggestion() {
        guard let info = defaults.dictionary(forKey: SettingsKey.lastSuggestion),
              let kind = info["kind"] as? String,
              let line = info["line"] as? String,
              let presetId = info["presetId"] as? String,
              let rule = PresetSerialization.rule(fromLine: line),
              var preset = presetLibrary.presets.first(where: { $0.id == presetId }) else { return }
        switch kind {
        case "blacklist": preset.redRules.removeAll { $0 == rule }
        case "presetAdjust": preset.greenRules.append(rule)
        default: break
        }
        presetLibrary.upsert(preset)
        defaults.removeObject(forKey: SettingsKey.lastSuggestion)
    }

    // MARK: - helpers

    private func configureUICallbacks() {
        island.model.onTap = { [weak self] in self?.snapBackGesture() }
        island.model.onLongPress = { [weak self] in self?.slackGesture() }
        island.model.onSwipeUp = { [weak self] in self?.pauseGesture() }
        island.hapticsEnabled = {
            UserDefaults.standard.object(forKey: SettingsKey.hapticsEnabled) == nil
                || UserDefaults.standard.bool(forKey: SettingsKey.hapticsEnabled)
        }
        fog.isEnabled = {
            let d = UserDefaults.standard
            let frictionOn = d.object(forKey: SettingsKey.frictionEnabled) == nil || d.bool(forKey: SettingsKey.frictionEnabled)
            return frictionOn && !d.bool(forKey: SettingsKey.reduceFriction)
        }
        inputFriction.isEnabled = {
            UserDefaults.standard.bool(forKey: SettingsKey.inputFrictionEnabled)
                && !UserDefaults.standard.bool(forKey: SettingsKey.reduceFriction)
        }
        hotkeys.onSnapBack = { [weak self] in self?.snapBackGesture() }
        hotkeys.onSlack = { [weak self] in self?.slackGesture() }
        hotkeys.onPause = { [weak self] in self?.pauseGesture() }
        hotkeys.onLockToggle = { [weak self] in self?.toggleLockHotkey() }
    }

    private func rebuildReducer(for preset: Preset) {
        reducer = StateReducer(driftThreshold: preset.driftThresholdSeconds, slackingDuration: 300)
        renderIsland()
        reclassifyFrontmost() // 规则/preset 变更立即生效（设计稿：互斥 + 立即重判）
    }

    private func zone(of state: AnchorState) -> ZoneClassification? {
        switch state {
        case .green: return .green
        case .drifting: return .gray
        case .red: return .red
        case .slacking: return .gray // 合法摸鱼：在线但不算专注，也不惩罚
        case .paused, .offline: return nil
        }
    }

    private func isRed(_ state: AnchorState) -> Bool {
        if case .red = state { return true }
        return false
    }

    private func greenContext(of state: AnchorState) -> AppContext? {
        if case let .green(ctx) = state { return ctx }
        return nil
    }

    private func nonGreenContext(of state: AnchorState) -> AppContext? {
        switch state {
        case let .drifting(_, ctx): return ctx
        case let .red(ctx): return ctx
        default: return nil
        }
    }
}
