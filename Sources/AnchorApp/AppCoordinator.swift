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
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var midnightTimer: Timer?
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
        pruneOldDataIfNeeded()
        openSession()
        // 上次退出时若还连着扩展，这个键会留着 true——不重置的话设置里会谎报"已连接"。
        defaults.set(false, forKey: SettingsKey.extensionConnected)

        // rebuildReducer 内部会对当前前台 app 立即重判（此时 session/日志器已就绪）。
        rebuildReducer(for: presetLibrary.activePreset)

        observeFrontmostApp()
        observeSleepWake()
        scheduleMidnightRollover()
        startDaemon()
        if defaults.object(forKey: SettingsKey.hotkeysEnabled) == nil
            || defaults.bool(forKey: SettingsKey.hotkeysEnabled) {
            hotkeys.start()
        }
        scheduleRecapTimers()
        startCheckpointTimer()

        onStateChange?(state)
    }

    func stop() {
        let center = NSWorkspace.shared.notificationCenter
        for observer in [workspaceObserver, sleepObserver, wakeObserver].compactMap({ $0 }) {
            center.removeObserver(observer)
        }
        workspaceObserver = nil
        sleepObserver = nil
        wakeObserver = nil
        hotkeys.stop()
        tickTimer?.invalidate()
        checkpointTimer?.invalidate()
        recapTimer?.invalidate()
        weeklyTimer?.invalidate()
        midnightTimer?.invalidate()
        redBuffer?.cancel()
        closeSession()
        daemon.stop()
        fog.clear()
        inputFriction.update(level: 0)
        // closeSession 的写是 `writeQueue.async`，而 applicationWillTerminate 返回后进程立刻退出——
        // 不等一下，收尾写就基本执行不到：ended_at 永远是 NULL（下次启动把正常退出误判成崩溃恢复），
        // 最后一条漂移记录直接丢失。这里加一道栅栏，把终态写等落盘。
        writeQueue.sync {}
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
            island.flashHint(L("hint.no_capture_target"))
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
        case .green: island.flashHint(L("hint.added_to_green", target.name))
        case .red: island.flashHint(L("hint.added_to_red", target.name))
        case .gray: island.flashHint(L("hint.moved_to_gray", target.name))
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
        island.flashHint(L("hint.locked", lock.label))
        reclassifyFrontmost()
    }

    func disengageLock() {
        guard focusLock != nil else { return }
        focusLock = nil
        island.model.locked = false
        island.flashHint(L("hint.unlocked"))
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
            island.flashHint(L("hint.no_lock_target"))
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
        // 中文的「第 N 次」是序数，英语等语言没有对应的位置参数写法——文案改成中性计数，
        // 由译文自己决定怎么说；分钟数也从字面量里抽成参数，改配置不必改译文。
        let count = Int64(used + 1)
        island.flashHint(currentSlackMode == .hard
            ? L("hint.slack_started_hard", count)
            : L("hint.slack_started", Int64(reducer.slackingDuration / 60), count))
    }

    func pauseGesture() {
        // 已暂停时同一入口直接恢复（⌥⌘P / 菜单 / 岛点都是开关语义）。
        if case .paused = state {
            resumeGesture()
            return
        }
        guard let reason = PauseReasonPrompt.ask() else { return }
        handleEvent(.islandSwipedUp(reason: reason))
    }

    /// 恢复看护：退出 paused，并立刻对当前前台重新分类。
    func resumeGesture() {
        guard case .paused = state else { return }
        handleEvent(.sessionStarted)
        reclassifyFrontmost()
        island.flashHint(L("hint.resumed"))
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

    /// 睡眠 / 唤醒。
    ///
    /// 没有这段的话，合盖一晚等于"连续专注 8 小时"：`SessionAccumulator` 和 `DriftLogger`
    /// 都用墙上时钟算区间时长，于是 Deep Score、最长连续专注、罪人榜全被灌水
    /// （实测形态：合盖前停在 YouTube，第二天罪人榜写「#1 youtube.com · 666 分钟」）。
    /// 处理办法：入睡当作"下线"把当前区间收口，醒来重新判定前台。
    private func observeSleepWake() {
        let center = NSWorkspace.shared.notificationCenter
        sleepObserver = center.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleWillSleep() }
        }
        wakeObserver = center.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleDidWake() }
        }
    }

    private func handleWillSleep() {
        let now = Date()
        // 收口当前区间与进行中的漂移，别把睡眠时长算进任何一边。
        // 用 `.sessionEnd` 而不是 `.autoReturn`：用户并没有"回到绿区"，
        // 是这段被测量的时间到此为止了——复盘里的归因得对得上事实。
        if let closed = driftLogger?.returnToGreen(at: now, reason: .sessionEnd) {
            insert(closed)
        }
        accumulator.transition(to: nil, at: now)
        persistSession(endedAt: nil)
        fog.clear()
        inputFriction.update(level: 0)
        tickTimer?.invalidate()
        tickTimer = nil
    }

    private func handleDidWake() {
        // 跨过午夜就换一天的 session，否则今天的数据会记到昨天名下。
        if DayKey.key(for: sessionStartedAt) != DayKey.key(for: Date()) {
            rollOverSession()
        }
        accumulator.transition(to: zone(of: state), at: Date())
        reclassifyFrontmost()
        scheduleMidnightRollover()
    }

    /// 本地午夜切分 session。
    ///
    /// 菜单栏 app 会一直挂着，而 `composeRecap` 查的是 `started_at >= 今天零点`——
    /// 一个从不换 session 的进程，从第二天起这个查询恒为空，于是 22:00 复盘显示
    /// Deep Score **0**、时间线全空、叙事写"今天你有 0 分钟的真正专注"，
    /// 而罪人榜却有数据。产品的头号日常交付物从第二天开始就是坏的。
    private func scheduleMidnightRollover() {
        midnightTimer?.invalidate()
        let calendar = Calendar.current
        guard let nextMidnight = calendar.nextDate(
            after: Date(),
            matching: DateComponents(hour: 0, minute: 0, second: 5),
            matchingPolicy: .nextTime
        ) else { return }
        // 每次触发后重新算下一次，而不是用固定 86400 间隔——这样夏令时切换不会把时刻带偏。
        let timer = Timer(fire: nextMidnight, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.rollOverSession()
                self.scheduleMidnightRollover()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        midnightTimer = timer
    }

    /// 收口当前 session 并立刻开一份新的（跨天 / 唤醒后跨天时调用）。
    private func rollOverSession() {
        closeSession()
        openSession()
        accumulator.transition(to: zone(of: state), at: Date())
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
        let askToExtendSlack = bookkeep(from: state, to: next, event: event)
        state = next
        apply(effects)
        manageTickTimer()
        // 必须等状态落定后再弹模态框。
        // 之前 bookkeep 里直接 runModal()：模态是嵌套 run loop，用户点「再来 5 分钟」会
        // 重入 handleEvent 把 state 设成 .slacking，等模态返回，外层这一帧再执行
        // `state = next`（.offline）把刚发的 5 分钟**覆盖掉**——功能在肯定分支上完全失效，
        // 且已经扣掉了一次日额度。
        if askToExtendSlack {
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated { self?.askForSlackExtension() }
            }
        }
    }

    /// 状态迁移时的记账：时间累计、漂移日志、绿区栈、红区缓冲。
    ///
    /// **纯记账，不改 state、不弹模态**。返回值 = 是否需要在状态落定后询问「还要 5 分钟吗」。
    @discardableResult
    private func bookkeep(from old: AnchorState, to new: AnchorState, event: AnchorEvent) -> Bool {
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

        // 软上限摸鱼到点：交给调用方在状态落定后再问"还要 5 分钟吗？"
        if case .slacking = old, case .offline = new, currentSlackMode == .soft {
            return true
        }
        return false
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
                browserOverlayActive = false
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

    /// 「没有锚点，就没有橡皮筋。」
    ///
    /// friction 的全部意义是**把你拉回某个地方**。如果这一刻压根没有可拉回的目标
    /// （刚装上还没进过任何绿区 app、或当前场景没有绿区规则），糊屏幕就只是无来由的惩罚：
    /// 用户既不知道为什么，也无处可去——单击岛也只会弹"暂无可拉回的目标"。
    ///
    /// 这一条同时修掉三个首启事故：新用户装完在 Finder 里被糊、点岛无效后下一秒又被糊回来、
    /// 以及「随便看看」这个本该是逃生口的场景反而永久重度模糊。
    private var hasAnchor: Bool {
        lastGreen.snapBackTarget != nil
    }

    /// 浏览器内遮罩是否已下发（避免 1Hz 重复广播，也保证降级时能撤掉）。
    private var browserOverlayActive = false

    private func applyFriction(level: Double) {
        let effective = hasAnchor ? level : 0
        fog.render(level: effective)
        inputFriction.update(level: effective)
        if effective >= FrictionLevel.heavy.blurIntensity {
            daemon.broadcast(command: .frictionOverlay(level: effective))
            browserOverlayActive = true
        } else if browserOverlayActive {
            // 此前只在"升到 heavy"时下发遮罩，却从不在降级时撤销：
            // 深度漂移后切到另一个灰区 tab/app，本地雾散了，但页面上的遮罩会一直留着
            // （content script 只认显式的 friction_clear），进红区更是永久留存。
            daemon.broadcast(command: .frictionClear)
            browserOverlayActive = false
        }
    }

    private func performSnapBack() {
        guard let target = lastGreen.snapBackTarget else {
            island.flashHint(L("hint.no_snapback_target"))
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
        let minutes = Int64(reducer.slackingDuration / 60)
        alert.messageText = L("alert.slack_extend.title", minutes)
        let remaining = max(0, slackingPolicy.softLimitPerDay - slackingCounter.usedToday)
        alert.informativeText = L("alert.slack_extend.message", minutes, Int64(remaining))
        alert.addButton(withTitle: L("alert.slack_extend.back_to_work"))
        alert.addButton(withTitle: L("alert.slack_extend.extend", minutes))
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
            snapBackName: lastGreen.snapBackTarget.map { ctx in
                // 岛上空间金贵：app 名超长截断，避免展开面板被文本撑得比刘海宽。
                let name = displayName(for: ctx)
                return name.count > 12 ? String(name.prefix(11)) + "…" : name
            }
        )
    }

    private func displayName(for ctx: AppContext) -> String {
        NSWorkspace.shared.runningApplications
            .first { $0.bundleIdentifier == ctx.bundleId }?.localizedName ?? ctx.destinationLabel
    }

    // MARK: - session persistence (PR #23)

    /// 启动时按留存策略清理老数据（默认 90 天，可在设置里调到"永久保留"）。
    /// 无上限增长既是隐私负担也是性能负担——但删除是用户的选择，所以设置里能关。
    private func pruneOldDataIfNeeded() {
        guard let store else { return }
        let stored = defaults.object(forKey: SettingsKey.retentionDays) as? Int
        let days = stored ?? SessionStore.defaultRetentionDays
        guard days > 0 else { return } // 0 = 永久保留
        writeQueue.async {
            if let removed = try? store.prune(olderThanDays: days), removed > 0 {
                NSLog("[Anchor] pruned %d rows older than %d days", removed, days)
            }
        }
    }

    // MARK: - 数据导出 / 清除（Settings「隐私与数据」调用）

    /// 导出全部数据到用户选定的文件。I/O 在写队列上，回调回主线程。
    func exportData(to url: URL, completion: @escaping @MainActor (Error?) -> Void) {
        persistSession(endedAt: nil) // 让进行中的数据也进库，导出才是完整的
        guard let store else {
            Task { @MainActor in completion(SessionStoreUnavailable()) }
            return
        }
        writeQueue.async {
            var failure: Error?
            do {
                try store.exportJSON().write(to: url, options: .atomic)
            } catch {
                failure = error
            }
            Task { @MainActor in completion(failure) }
        }
    }

    /// 清除全部历史（保留 preset），并把进行中的 session 重新开一份。
    func wipeHistory(completion: @escaping @MainActor (Error?) -> Void) {
        guard let store else {
            Task { @MainActor in completion(SessionStoreUnavailable()) }
            return
        }
        writeQueue.async { [weak self] in
            var failure: Error?
            do {
                try store.wipeHistory()
            } catch {
                failure = error
            }
            Task { @MainActor in
                guard let self else { completion(failure); return }
                // 刚被删掉的 session 不能继续往里累计，开一份干净的。
                self.accumulator = SessionAccumulator()
                self.openSession()
                completion(failure)
            }
        }
    }

    struct SessionStoreUnavailable: LocalizedError {
        var errorDescription: String? { L("error.local_database_unavailable") }
    }

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
                self?.island.flashHint(L("hint.recap_ready"))
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
        // 用 displayName：内置场景的 name 是首次启动时冻进库里的，
        // 直接用它会让英文环境的复盘写着「场景：写代码」。
        let presetName = presetLibrary.activePreset.displayName
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
                // 稳定 key（locale 无关）——它同时是 daily_recaps 的主键，
                // 显示时由 RecapView 转成本地化文案（见 DayKey）。
                let data = RecapComposer.compose(
                    dateLabel: DayKey.key(for: Date()),
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
        let presetName = preset.displayName // 同上：周建议文案也要跟随当前语言

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
        alert.messageText = L("alert.weekly_suggestion.title")
        alert.informativeText = L("alert.weekly_suggestion.body", suggestion.message, suggestion.rationale)
        alert.addButton(withTitle: L("alert.weekly_suggestion.apply"))
        alert.addButton(withTitle: L("alert.weekly_suggestion.skip"))
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
            island.flashHint(L("hint.rhythm_suggestion", suggestion.target))
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
        reducer = StateReducer(
            driftThreshold: preset.driftThresholdSeconds,
            slackingDuration: 300,
            interveneEnabled: !preset.isObserveOnly
        )
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
