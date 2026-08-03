import AppKit
import AnchorCore
import AnchorDaemon
import Sparkle

/// App 入口：menu bar、coordinator 生命周期、Sparkle 自动更新。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private var statusItem: NSStatusItem?
    private var statusMenuItem: NSMenuItem?
    private var presetMenu: NSMenu?
    private var pauseItem: NSMenuItem?
    private var captureGreenItem: NSMenuItem?
    private var captureRedItem: NSMenuItem?
    private var captureGrayItem: NSMenuItem?
    private var lockPageItem: NSMenuItem?
    private var lockSiteItem: NSMenuItem?
    private var lockAppItem: NSMenuItem?
    private var unlockItem: NSMenuItem?
    private var settingsWindowController: SettingsWindowController?
    private var onboardingWindowController: OnboardingWindowController?
    private let coordinator = AppCoordinator()

    /// Sparkle 只在真正的 .app bundle 里启动（`swift run` 没有 Info.plist，会启动失败）。
    private var updaterController: SPUStandardUpdaterController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 本地化自检。查表失败在这个架构里是**静默**的（会回落到 key 而非报错），
        // 所以启动时留一行日志，出问题时能一眼看出是"表没打进包"还是"语言没选中"。
        NSLog("[Anchor] l10n selftest=%@ lang=%@ bundle=%@",
              L("l10n.selftest"),
              Bundle.main.preferredLocalizations.first ?? "?",
              Bundle.main.bundlePath)
        // 仅在真 .app bundle 且配置了真实更新源时启动 Sparkle——
        // 占位 feed（example.invalid）会让自动检查弹 "Unable to Check For Updates"。
        let feedURL = Bundle.main.infoDictionary?["SUFeedURL"] as? String
        if Bundle.main.bundleIdentifier != nil,
           let feedURL, !feedURL.contains("example.invalid") {
            updaterController = SPUStandardUpdaterController(
                startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil
            )
        }
        setupStatusItem()
        coordinator.onStateChange = { [weak self] state in
            self?.updateStatus(state)
        }
        // 入口统一到岛：左键绿点 / 右键任何状态，都弹完整菜单——
        // 不依赖菜单栏图标（会被挤掉）、不用快捷键。
        coordinator.island.model.onDotTap = { [weak self] in
            self?.popUpStatusMenu()
        }
        coordinator.island.model.onSecondaryClick = { [weak self] in
            self?.popUpStatusMenu()
        }
        NotificationCenter.default.addObserver(
            forName: .anchorMenuBarIconChanged, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.statusItem?.isVisible = !UserDefaults.standard.bool(forKey: SettingsKey.hideMenuBarIcon)
            }
        }
        coordinator.start()
        rebuildPresetMenu()

        // 首启引导。放在 start() 之后：引导第二页要让用户选场景，需要 presetLibrary 已就绪。
        // 这是唯一一处"抢焦点"正确的场景——用户刚双击了 app，本来就在等着看东西。
        if OnboardingWindowController.needsOnboarding {
            showOnboarding()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator.stop()
    }

    // MARK: - menu bar

    private func setupStatusItem() {
        // 纯图标固定宽：刘海机型菜单栏寸土寸金，宽文字项会被系统整个藏掉
        // （实时状态看灵动岛；文字状态在 tooltip 和菜单首行）。
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = StatusBarIcon.make()
            button.toolTip = L("statusitem.tooltip")
        }
        // 菜单栏太挤的人可隐藏图标——岛右键即是完整入口，不会因此失去操作能力。
        item.isVisible = !UserDefaults.standard.bool(forKey: SettingsKey.hideMenuBarIcon)
        let menu = NSMenu()
        menu.autoenablesItems = false // 收编项的可用性由 menuNeedsUpdate 手动控制

        let statusLine = NSMenuItem(title: L("menu.status_prefix", "—"), action: nil, keyEquivalent: "")
        menu.addItem(statusLine)
        self.statusMenuItem = statusLine

        let presetItem = NSMenuItem(title: L("menu.scenes"), action: nil, keyEquivalent: "")
        let presetSubmenu = NSMenu()
        presetItem.submenu = presetSubmenu
        self.presetMenu = presetSubmenu
        menu.addItem(presetItem)

        menu.addItem(.separator())
        menu.addItem(makeItem(L("menu.snap_back"), #selector(snapBack), "a"))
        menu.addItem(makeItem(L("menu.sanctioned_break"), #selector(slack), "b"))
        let pauseItem = makeItem(L("menu.pause_watch"), #selector(pause), "p")
        menu.addItem(pauseItem)
        self.pauseItem = pauseItem
        menu.addItem(.separator())
        let captureGreen = NSMenuItem(title: L("menu.capture.green_generic"), action: #selector(captureToGreen), keyEquivalent: "")
        let captureRed = NSMenuItem(title: L("menu.capture.red_generic"), action: #selector(captureToRed), keyEquivalent: "")
        let captureGray = NSMenuItem(title: L("menu.capture.gray_generic"), action: #selector(captureToGray), keyEquivalent: "")
        menu.addItem(captureGreen)
        menu.addItem(captureRed)
        menu.addItem(captureGray)
        self.captureGreenItem = captureGreen
        self.captureRedItem = captureRed
        self.captureGrayItem = captureGray
        menu.addItem(.separator())

        // Focus Lock（"只看这个"）：页/站/app 三个入口按上下文显隐；锁定后只剩"解除"。
        let lockPage = makeItem(L("menu.lock.page"), #selector(lockToPage), "l")
        let lockSite = NSMenuItem(title: L("menu.lock.site"), action: #selector(lockToSite), keyEquivalent: "")
        let lockApp = NSMenuItem(title: L("menu.lock.app"), action: #selector(lockToApp), keyEquivalent: "")
        let unlock = makeItem(L("menu.lock.release"), #selector(unlockFocus), "l")
        // 默认全部隐藏，由 updateLockItems() 按上下文点亮——否则首次打开菜单时
        // 四项（含一个"解除锁定"）会全部可见且点了没反应。
        for item in [lockPage, lockSite, lockApp, unlock] {
            item.isHidden = true
            menu.addItem(item)
        }
        self.lockPageItem = lockPage
        self.lockSiteItem = lockSite
        self.lockAppItem = lockApp
        self.unlockItem = unlock
        menu.addItem(.separator())
        menu.addItem(.init(title: L("menu.recap"), action: #selector(showRecap), keyEquivalent: "r"))
        // 引导可以随时重看——它是产品词汇（绿/灰/红、三手势）唯一被解释的地方。
        menu.addItem(.init(title: L("menu.getting_started"), action: #selector(showOnboardingFromMenu), keyEquivalent: ""))
        menu.addItem(.init(title: L("menu.settings"), action: #selector(showSettings), keyEquivalent: ","))
        menu.addItem(.init(title: L("menu.check_updates"), action: #selector(checkForUpdates), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(.init(title: L("menu.quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menu.delegate = self
        item.menu = menu
        self.statusItem = item
    }

    /// ⌥⌘ 组合键的菜单等效（spec §七）；真正的全局热键由 HotkeyMonitor 负责。
    private func makeItem(_ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = [.control, .option, .command]
        return item
    }

    private func rebuildPresetMenu() {
        guard let presetMenu, let library = coordinator.presetLibrary else { return }
        presetMenu.removeAllItems()
        for preset in library.presets {
            let item = NSMenuItem(title: preset.displayName, action: #selector(switchPreset(_:)), keyEquivalent: "")
            item.representedObject = preset.id
            item.state = preset.id == library.activePresetId ? .on : .off
            presetMenu.addItem(item)
        }
    }

    private func updateStatus(_ state: AnchorState) {
        let label = StatusLabel.text(for: state)
        statusItem?.button?.toolTip = L("statusitem.tooltip_status", label)
        statusMenuItem?.title = L("menu.status_prefix", label)
    }

    // MARK: - actions

    private func popUpStatusMenu() {
        guard let menu = statusItem?.menu else { return }
        menuNeedsUpdate(menu)
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    @objc private func snapBack() { coordinator.snapBackGesture() }
    @objc private func slack() { coordinator.slackGesture() }
    @objc private func pause() { coordinator.pauseGesture() }
    @objc private func captureToGreen() { coordinator.captureCurrent(as: .green) }
    @objc private func captureToRed() { coordinator.captureCurrent(as: .red) }
    @objc private func captureToGray() { coordinator.captureCurrent(as: .gray) }

    @objc private func lockToPage() {
        if let lock = coordinator.lockCandidates?.page { coordinator.engageLock(lock) }
    }

    @objc private func lockToSite() {
        if let lock = coordinator.lockCandidates?.site { coordinator.engageLock(lock) }
    }

    @objc private func lockToApp() {
        if let lock = coordinator.lockCandidates?.app?.lock { coordinator.engageLock(lock) }
    }

    @objc private func unlockFocus() { coordinator.disengageLock() }

    @objc private func switchPreset(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        coordinator.presetLibrary.switchTo(id: id)
        rebuildPresetMenu()
    }

    @objc private func showRecap() {
        coordinator.openRecapWindow()
    }

    @objc private func showOnboardingFromMenu() {
        showOnboarding()
    }

    private func showOnboarding() {
        guard let library = coordinator.presetLibrary else { return }
        if onboardingWindowController == nil {
            onboardingWindowController = OnboardingWindowController(library: library)
        }
        onboardingWindowController?.show()
    }

    @objc private func showSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(coordinator: coordinator)
        }
        settingsWindowController?.show()
    }

    // MARK: - NSMenuDelegate（菜单展开时刷新收编项：标题 + 当前归属打钩 + 冗余动作置灰）

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildPresetMenu()
        // 暂停/恢复是同一开关入口
        if case .paused = coordinator.state {
            pauseItem?.title = L("menu.resume_watch")
        } else {
            pauseItem?.title = L("menu.pause_watch")
        }
        // 锁定项与收编项互不相干，必须先刷新——此前这一步被下面的 early return 跳过了。
        updateLockItems()

        guard let target = coordinator.captureTarget else {
            captureGreenItem?.title = L("menu.capture.green_generic")
            captureRedItem?.title = L("menu.capture.red_generic")
            captureGrayItem?.title = L("menu.capture.gray_generic")
            for item in [captureGreenItem, captureRedItem, captureGrayItem] {
                item?.isEnabled = false
                item?.state = .off
            }
            return
        }

        // 浏览器但扩展未连（拿不到 tab）→ 只能收编整个应用，标题说清楚。
        let suffix = target.isWholeBrowserApp ? L("menu.capture.whole_app_suffix") : ""
        captureGreenItem?.title = L("menu.capture.green_named", target.name, suffix)
        captureRedItem?.title = L("menu.capture.red_named", target.name, suffix)
        captureGrayItem?.title = L("menu.capture.gray_named", target.name)

        // 已在名单的项：打钩 + 置灰（无需重复执行）；移回灰区只在已列入时可点。
        captureGreenItem?.state = target.membership == .green ? .on : .off
        captureRedItem?.state = target.membership == .red ? .on : .off
        captureGrayItem?.state = .off
        captureGreenItem?.isEnabled = target.membership != .green
        captureRedItem?.isEnabled = target.membership != .red
        captureGrayItem?.isEnabled = target.membership != nil
    }

    /// Focus Lock 菜单项：锁定中只显示「解除锁定」；未锁按上下文显示 页/站/app。
    private func updateLockItems() {
        if let lock = coordinator.focusLock {
            unlockItem?.isHidden = false
            unlockItem?.isEnabled = true
            unlockItem?.title = L("menu.lock.release_named", lock.label)
            lockPageItem?.isHidden = true
            lockSiteItem?.isHidden = true
            lockAppItem?.isHidden = true
            return
        }
        unlockItem?.isHidden = true

        let candidates = coordinator.lockCandidates
        if let page = candidates?.page {
            lockPageItem?.isHidden = false
            lockPageItem?.isEnabled = true
            lockPageItem?.title = L("menu.lock.page_named", truncate(page.label))
        } else {
            lockPageItem?.isHidden = true
        }
        if let site = candidates?.site {
            lockSiteItem?.isHidden = false
            lockSiteItem?.isEnabled = true
            lockSiteItem?.title = L("menu.lock.site_named", site.label)
        } else {
            lockSiteItem?.isHidden = true
        }
        if let app = candidates?.app {
            lockAppItem?.isHidden = false
            lockAppItem?.isEnabled = true
            let suffix = app.isWholeBrowserApp ? L("menu.lock.whole_browser_suffix") : ""
            lockAppItem?.title = L("menu.lock.app_named", app.lock.label, suffix)
        } else {
            lockAppItem?.isHidden = true
        }
    }

    private func truncate(_ text: String, max: Int = 36) -> String {
        text.count > max ? String(text.prefix(max)) + "…" : text
    }

    @objc private func checkForUpdates() {
        guard let updaterController else {
            // 之前这里写的是"见 scripts/appcast-template.xml"——把仓库里的构建脚本路径
            // 甩给终端用户看。改成用户真的能执行的动作。
            let alert = NSAlert()
            alert.messageText = L("alert.no_update_feed.title")
            alert.informativeText = L("alert.no_update_feed.message")
            alert.addButton(withTitle: L("alert.no_update_feed.open_releases"))
            alert.addButton(withTitle: L("alert.no_update_feed.ok"))
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn,
               let url = URL(string: "https://github.com/TIFOSI528/anchor/releases/latest") {
                NSWorkspace.shared.open(url)
            }
            return
        }
        updaterController.checkForUpdates(nil)
    }
}
