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
    private let coordinator = AppCoordinator()

    /// Sparkle 只在真正的 .app bundle 里启动（`swift run` 没有 Info.plist，会启动失败）。
    private var updaterController: SPUStandardUpdaterController?

    func applicationDidFinishLaunching(_ notification: Notification) {
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
            button.toolTip = "Anchor — 桅杆上的瞭望员"
        }
        // 菜单栏太挤的人可隐藏图标——岛右键即是完整入口，不会因此失去操作能力。
        item.isVisible = !UserDefaults.standard.bool(forKey: SettingsKey.hideMenuBarIcon)
        let menu = NSMenu()
        menu.autoenablesItems = false // 收编项的可用性由 menuNeedsUpdate 手动控制

        let statusLine = NSMenuItem(title: "当前状态：—", action: nil, keyEquivalent: "")
        menu.addItem(statusLine)
        self.statusMenuItem = statusLine

        let presetItem = NSMenuItem(title: "场景", action: nil, keyEquivalent: "")
        let presetSubmenu = NSMenu()
        presetItem.submenu = presetSubmenu
        self.presetMenu = presetSubmenu
        menu.addItem(presetItem)

        menu.addItem(.separator())
        menu.addItem(makeItem("立即拉回", #selector(snapBack), "a"))
        menu.addItem(makeItem("合法摸鱼 5 分钟", #selector(slack), "b"))
        let pauseItem = makeItem("暂停看护...", #selector(pause), "p")
        menu.addItem(pauseItem)
        self.pauseItem = pauseItem
        menu.addItem(.separator())
        let captureGreen = NSMenuItem(title: "把当前 app 加入绿区", action: #selector(captureToGreen), keyEquivalent: "")
        let captureRed = NSMenuItem(title: "把当前 app 加入红区", action: #selector(captureToRed), keyEquivalent: "")
        let captureGray = NSMenuItem(title: "移回灰区", action: #selector(captureToGray), keyEquivalent: "")
        menu.addItem(captureGreen)
        menu.addItem(captureRed)
        menu.addItem(captureGray)
        self.captureGreenItem = captureGreen
        self.captureRedItem = captureRed
        self.captureGrayItem = captureGray
        menu.addItem(.separator())

        // Focus Lock（"只看这个"）：页/站/app 三个入口按上下文显隐；锁定后只剩"解除"。
        let lockPage = makeItem("只看这个页面", #selector(lockToPage), "l")
        let lockSite = NSMenuItem(title: "只看这个站点", action: #selector(lockToSite), keyEquivalent: "")
        let lockApp = NSMenuItem(title: "只看这个 app", action: #selector(lockToApp), keyEquivalent: "")
        let unlock = makeItem("解除锁定", #selector(unlockFocus), "l")
        for item in [lockPage, lockSite, lockApp, unlock] { menu.addItem(item) }
        self.lockPageItem = lockPage
        self.lockSiteItem = lockSite
        self.lockAppItem = lockApp
        self.unlockItem = unlock
        menu.addItem(.separator())
        menu.addItem(.init(title: "今日复盘", action: #selector(showRecap), keyEquivalent: "r"))
        menu.addItem(.init(title: "设置...", action: #selector(showSettings), keyEquivalent: ","))
        menu.addItem(.init(title: "检查更新...", action: #selector(checkForUpdates), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(.init(title: "退出 Anchor", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
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
            let item = NSMenuItem(title: preset.name, action: #selector(switchPreset(_:)), keyEquivalent: "")
            item.representedObject = preset.id
            item.state = preset.id == library.activePresetId ? .on : .off
            presetMenu.addItem(item)
        }
    }

    private func updateStatus(_ state: AnchorState) {
        let label = StatusLabel.text(for: state)
        statusItem?.button?.toolTip = "Anchor · \(label)"
        statusMenuItem?.title = "当前状态：\(label)"
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
            pauseItem?.title = "恢复看护"
        } else {
            pauseItem?.title = "暂停看护..."
        }
        guard let target = coordinator.captureTarget else {
            captureGreenItem?.title = "把当前 app 加入绿区"
            captureRedItem?.title = "把当前 app 加入红区"
            captureGrayItem?.title = "移回灰区"
            for item in [captureGreenItem, captureRedItem, captureGrayItem] {
                item?.isEnabled = false
                item?.state = .off
            }
            return
        }

        // 浏览器但扩展未连（拿不到 tab）→ 只能收编整个应用，标题说清楚。
        let suffix = target.isWholeBrowserApp ? "（整个应用）" : ""
        captureGreenItem?.title = "把「\(target.name)」加入绿区\(suffix)"
        captureRedItem?.title = "把「\(target.name)」加入红区\(suffix)"
        captureGrayItem?.title = "把「\(target.name)」移回灰区"

        // 已在名单的项：打钩 + 置灰（无需重复执行）；移回灰区只在已列入时可点。
        captureGreenItem?.state = target.membership == .green ? .on : .off
        captureRedItem?.state = target.membership == .red ? .on : .off
        captureGrayItem?.state = .off
        captureGreenItem?.isEnabled = target.membership != .green
        captureRedItem?.isEnabled = target.membership != .red
        captureGrayItem?.isEnabled = target.membership != nil

        updateLockItems()
    }

    /// Focus Lock 菜单项：锁定中只显示「解除锁定」；未锁按上下文显示 页/站/app。
    private func updateLockItems() {
        if let lock = coordinator.focusLock {
            unlockItem?.isHidden = false
            unlockItem?.isEnabled = true
            unlockItem?.title = "解除锁定（\(lock.label)）"
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
            lockPageItem?.title = "只看这个页面（\(truncate(page.label))）"
        } else {
            lockPageItem?.isHidden = true
        }
        if let site = candidates?.site {
            lockSiteItem?.isHidden = false
            lockSiteItem?.isEnabled = true
            lockSiteItem?.title = "只看这个站点（\(site.label)）"
        } else {
            lockSiteItem?.isHidden = true
        }
        if let app = candidates?.app {
            lockAppItem?.isHidden = false
            lockAppItem?.isEnabled = true
            let suffix = app.isWholeBrowserApp ? "（整个浏览器，装扩展可锁到页面）" : ""
            lockAppItem?.title = "只看这个 app（\(app.lock.label)）\(suffix)"
        } else {
            lockAppItem?.isHidden = true
        }
    }

    private func truncate(_ text: String, max: Int = 36) -> String {
        text.count > max ? String(text.prefix(max)) + "…" : text
    }

    @objc private func checkForUpdates() {
        guard let updaterController else {
            let alert = NSAlert()
            alert.messageText = "暂无可用的更新源"
            alert.informativeText = "正式发布并配置 appcast 地址后，这里会检查更新（见 scripts/appcast-template.xml）。"
            alert.runModal()
            return
        }
        updaterController.checkForUpdates(nil)
    }
}
