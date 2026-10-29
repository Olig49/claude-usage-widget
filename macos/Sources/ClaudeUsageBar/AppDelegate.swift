import AppKit
import Combine
import SwiftUI
import UsageCore

/// Owns the menu bar item, the dropdown, the Settings window and the timers.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSPopoverDelegate {
    // Created in applicationDidFinishLaunching, on the main actor.
    private var store: UsageStore!
    private var loginItem: LoginItem!
    private var settings: SettingsController!
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var cancellables = Set<AnyCancellable>()
    private var tickTimer: Timer?
    /// When the popover last closed: the mouse-down on the icon closes a transient popover
    /// before our mouse-up action runs, which would otherwise reopen it.
    private var lastPopoverClose = Date.distantPast

    func applicationDidFinishLaunching(_ notification: Notification) {
        store = UsageStore()
        loginItem = LoginItem()
        installMainMenu()
        settings = SettingsController(store: store, loginItem: loginItem)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityLabel("Claude usage")
        }

        let actions = PopoverActions(
            refresh: { [weak self] in self?.store.refresh(manual: true) },
            scan: { [weak self] in self?.store.scan() },
            settings: { [weak self] in self?.openSettings() },
            openConfig: { [weak self] in self?.openConfig() },
            openLog: { [weak self] in self?.openLog() },
            openUpdate: { [weak self] in self?.openUpdatePage() },
            quit: { NSApp.terminate(nil) }
        )
        let hosting = NSHostingController(rootView: PopoverView(store: store, loginItem: loginItem, actions: actions))
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
        popover.behavior = .transient
        popover.delegate = self
        popover.animates = true

        // Redraw the rings whenever the data, config or Settings draft changes (after the change lands).
        store.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.redraw() }
            .store(in: &cancellables)

        // A light/dark switch changes the menu bar; redraw so text colours follow.
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(appearanceChanged),
            name: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil)

        // Catch up after sleep (give the network a few seconds to come back).
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)

        // Once a minute: refresh when due, keep countdowns fresh, and the daily update check.
        // Selector-based so the callback stays on the main thread (a closure here trips Swift's concurrency checks).
        tickTimer = Timer.scheduledTimer(timeInterval: 60, target: self, selector: #selector(tick),
                                         userInfo: nil, repeats: true)
        tickTimer?.tolerance = 10

        redraw()
        loginItem.enableOnFirstRun()
        store.start()
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in self?.store.checkForUpdates() }
    }

    /// A menu bar app has no main menu, and without an Edit menu ⌘V, ⌘C, ⌘X, ⌘A and ⌘Z don't reach
    /// text fields (e.g. pasting a token in Settings). This menu is never visible; it only routes the shortcuts.
    private func installMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        appMenu.addItem(withTitle: "Quit Claude Usage", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    // MARK: Drawing

    private func redraw() {
        guard let button = statusItem?.button else { return }
        let now = Date()
        button.image = RingRenderer.image(config: store.effective, accounts: store.menuBarAccounts(now: now),
                                          usage: store.usage, now: now)
        updateTooltip()
    }

    private func updateTooltip() {
        statusItem?.button?.toolTip = RingRenderer.tooltip(config: store.effective, accounts: store.menuBarAccounts(),
                                                           usage: store.usage)
    }

    @objc private func tick() {
        store.refreshIfDue()
        store.checkForUpdates()
        // Countdowns next to the rings and windows that just reset need a fresh image.
        redraw()
    }

    @objc private func appearanceChanged() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.redraw() }
    }

    @objc private func didWake() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.store.refreshIfDue() }
    }

    // MARK: Clicks

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let isRightClick = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        if isRightClick {
            showContextMenu()
        } else {
            togglePopover(sender)
        }
    }

    private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
            return
        }
        if Date().timeIntervalSince(lastPopoverClose) < 0.3 { return }
        store.notice = nil
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.delegate = self

        let refresh = NSMenuItem(title: "Refresh now", action: #selector(menuRefresh), keyEquivalent: "")
        refresh.isEnabled = store.canRefreshManually() && !store.refreshing
        menu.addItem(refresh)
        menu.addItem(NSMenuItem(title: "Settings\u{2026}", action: #selector(menuSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Scan for accounts", action: #selector(menuScan), keyEquivalent: ""))
        menu.addItem(.separator())
        let login = NSMenuItem(title: "Launch at login", action: #selector(menuToggleLogin), keyEquivalent: "")
        login.state = loginItem.isEnabled ? .on : .off
        menu.addItem(login)
        menu.addItem(NSMenuItem(title: "Open config file\u{2026}", action: #selector(menuOpenConfig), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Open log", action: #selector(menuOpenLog), keyEquivalent: ""))
        menu.addItem(.separator())
        if let update = store.update {
            menu.addItem(NSMenuItem(title: "Update available: \(update.version)\u{2026}",
                                    action: #selector(menuOpenUpdate), keyEquivalent: ""))
        }
        let about = NSMenuItem(title: "Claude Usage \(AppInfo.version)", action: nil, keyEquivalent: "")
        about.isEnabled = false
        menu.addItem(about)
        menu.addItem(NSMenuItem(title: "Uninstall\u{2026}", action: #selector(menuUninstall), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(menuQuit), keyEquivalent: "q"))
        for item in menu.items where item.action != nil { item.target = self }
        // Menus need autoenablesItems off for the manual isEnabled above to stick.
        menu.autoenablesItems = false

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
    }

    func popoverDidClose(_ notification: Notification) {
        lastPopoverClose = Date()
    }

    func menuDidClose(_ menu: NSMenu) {
        // Detach so the next left click opens the dropdown again.
        statusItem.menu = nil
    }

    @objc private func menuRefresh() { store.refresh(manual: true) }
    @objc private func menuSettings() { openSettings() }
    @objc private func menuScan() { store.scan() }
    @objc private func menuToggleLogin() { loginItem.setEnabled(!loginItem.isEnabled) }
    @objc private func menuOpenConfig() { openConfig() }
    @objc private func menuOpenLog() { openLog() }
    @objc private func menuOpenUpdate() { openUpdatePage() }
    @objc private func menuUninstall() { Uninstaller.confirmAndRun(store: store, loginItem: loginItem) }
    @objc private func menuQuit() { NSApp.terminate(nil) }

    // MARK: Windows and files

    private func openSettings() {
        popover.performClose(nil)
        settings.show()
    }

    private func openUpdatePage() {
        popover.performClose(nil)
        NSWorkspace.shared.open(store.update?.url ?? UpdateChecker.releasesPage)
    }

    private func openConfig() {
        let url = store.configStore.configURL
        if !FileManager.default.fileExists(atPath: url.path) {
            try? store.configStore.save(store.config)
        }
        openInTextEditor(url)
    }

    private func openLog() {
        let url = store.configStore.logURL
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? Data().write(to: url)
        }
        openInTextEditor(url)
    }

    /// `open -t` opens the file in the default text editor (a .json would otherwise go to Xcode or a browser).
    private func openInTextEditor(_ url: URL) {
        popover.performClose(nil)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-t", url.path]
        try? p.run()
    }
}
