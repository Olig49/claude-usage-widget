import Foundation
import UsageCore

/// The app's state: config, the Settings draft, the last usage per account, refresh scheduling
/// and the update check.
@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var config = AppConfig()
    /// Settings edits, previewed live in the menu bar until OK / Apply (nil when Settings is closed).
    @Published var draft: AppConfig?
    @Published private(set) var usage: [String: AccountUsage] = [:]
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var refreshing = false
    @Published private(set) var scanning = false
    /// A short message under the list ("Added 1 account").
    @Published var notice: String?
    @Published private(set) var update: ReleaseInfo?
    @Published private(set) var updateStatus: String?

    let configStore = ConfigStore()
    private let fetcher = UsageFetcher()
    private var lastManualRefresh: Date?
    private var refreshAgain = false

    /// What the menu bar and list show: the draft while Settings is open.
    var effective: AppConfig { draft ?? config }
    var visibleAccounts: [AccountConfig] { effective.visibleAccounts }
    func menuBarAccounts(now: Date = Date()) -> [AccountConfig] { effective.menuBarAccounts(usage: usage, now: now) }
    var hasUnsavedChanges: Bool { draft != nil && draft != config }

    /// Manual refresh at most once a minute, like the Windows widget.
    func canRefreshManually(now: Date = Date()) -> Bool {
        guard let last = lastManualRefresh else { return true }
        return now.timeIntervalSince(last) >= 60
    }

    /// First launch (or no accounts yet): find the Claude Code logins and write a config.
    func start() {
        Log.url = configStore.logURL
        if configStore.exists { reloadConfig() }
        if configStore.exists && !config.accounts.isEmpty {
            refresh()
        } else {
            scan(firstRun: true)
        }
    }

    func reloadConfig() {
        do {
            if let c = try configStore.load() { config = c }
        } catch {
            notice = "config.json couldn't be read; using the last good settings"
            Log.write("config: \(error)")
        }
    }

    private func save() {
        do { try configStore.save(config) } catch {
            notice = "Couldn't save settings"
            Log.write("save config: \(error)")
        }
    }

    // MARK: Refresh

    func refreshIfDue(now: Date = Date()) {
        guard let last = lastRefresh else { refresh(); return }
        if now.timeIntervalSince(last) >= Double(config.effectiveRefreshMinutes * 60) {
            refresh()
        }
    }

    /// `manual` is the refresh button (rate-limited); `force` is for changes that need fresh numbers now.
    func refresh(manual: Bool = false, force: Bool = false) {
        if refreshing || scanning {
            if force { refreshAgain = true }
            return
        }
        if manual {
            guard canRefreshManually() else { return }
            lastManualRefresh = Date()
            notice = nil
        }
        // Picks up hand edits to config.json.
        reloadConfig()
        let accounts = effective.visibleAccounts
        refreshing = true
        Task {
            for account in accounts {
                let result = await fetcher.fetch(account)
                usage[account.name] = result
            }
            // Forget accounts that were removed.
            let names = Set(config.accounts.map(\.name) + (draft?.accounts.map(\.name) ?? []))
            usage = usage.filter { names.contains($0.key) }
            lastRefresh = Date()
            refreshing = false
            if refreshAgain {
                refreshAgain = false
                refresh()
            }
        }
    }

    // MARK: Changes from the dropdown

    func setInMenuBar(_ name: String, _ on: Bool) {
        reloadConfig()
        guard let i = config.accounts.firstIndex(where: { $0.name == name }) else { return }
        config.accounts[i].menuBar = on
        save()
        if var d = draft, let j = d.accounts.firstIndex(where: { $0.name == name }) {
            d.accounts[j].menuBar = on
            draft = d
        }
    }

    // MARK: Settings

    func beginEditing() {
        reloadConfig()
        draft = config
    }

    /// Apply: saves the draft. Token accounts removed in Settings lose their Keychain token now.
    func applyDraft() {
        guard let d = draft else { return }
        let removed = config.accounts.filter { a in !d.accounts.contains { $0.name == a.name } }
        for a in removed where a.sourceKind == .token {
            TokenStore.delete(account: a.name)
        }
        let accountsChanged = d.accounts != config.accounts
        config = d
        save()
        draft = d
        if accountsChanged { refresh(force: true) }
    }

    /// OK applies and closes; Cancel just closes (the menu bar goes back to the saved settings).
    func endEditing(save: Bool) {
        if save { applyDraft() }
        draft = nil
    }

    /// Adds an account at once (saved immediately, like the Windows widget's approved token),
    /// storing a pasted token in the Keychain first.
    func addAccount(_ account: AccountConfig, token: String?) throws {
        if let token {
            try TokenStore.save(token.trimmingCharacters(in: .whitespacesAndNewlines), account: account.name)
        }
        reloadConfig()
        var a = account
        if !config.accounts.contains(where: { $0.isInMenuBar }) { a.menuBar = true }
        config.accounts.append(a)
        save()
        if var d = draft {
            d.accounts.append(a)
            draft = d
        }
        fetcher.forget(a.name)
        refresh(force: true)
    }

    /// Replaces the Keychain token of an existing token account.
    func replaceToken(for name: String, with token: String) throws {
        try TokenStore.save(token.trimmingCharacters(in: .whitespacesAndNewlines), account: name)
        fetcher.forget(name)
        refresh(force: true)
    }

    /// A name for a new account, unique across the saved config and the draft.
    func uniqueName(from label: String) -> String {
        var all = config
        all.accounts += (draft?.accounts ?? []).filter { d in !config.accounts.contains { $0.name == d.name } }
        return all.uniqueName(from: label)
    }

    /// Claude Code logins on this Mac that aren't in the config (or draft) yet.
    func findNewLogins() async -> [AccountConfig] {
        let found = await Task.detached(priority: .utility) { ClaudeCode.discover() }.value
        var probe = effective
        let before = probe.accounts.count
        ClaudeCode.merge(found, into: &probe)
        return Array(probe.accounts.dropFirst(before)).map { a in
            var a = a
            a.menuBar = nil
            return a
        }
    }

    /// Looks for Claude Code logins that aren't in the config yet and adds them.
    func scan(firstRun: Bool = false) {
        guard !scanning else { return }
        scanning = true
        notice = firstRun ? nil : "Looking for Claude Code logins\u{2026}"
        Task {
            let found = await Task.detached(priority: .utility) { ClaudeCode.discover() }.value
            if !firstRun { reloadConfig() }
            var cfg = config
            let added = ClaudeCode.merge(found, into: &cfg)
            config = cfg
            if added > 0 || firstRun { save() }
            if var d = draft {
                ClaudeCode.merge(found, into: &d)
                draft = d
            }
            scanning = false
            notice = firstRun ? nil
                : (added == 0 ? "No new Claude Code logins found" : "Added \(added) account\(added == 1 ? "" : "s")")
            refresh()
        }
    }

    // MARK: Updates

    private let lastUpdateCheckKey = "lastUpdateCheck"

    /// Daily when enabled; `manual` from the Updates tab.
    func checkForUpdates(manual: Bool = false) {
        if !manual {
            guard config.updateCheckEnabled else { return }
            if let last = UserDefaults.standard.object(forKey: lastUpdateCheckKey) as? Date,
               Date().timeIntervalSince(last) < 24 * 3600 { return }
        }
        updateStatus = manual ? "Checking\u{2026}" : updateStatus
        Task {
            let latest = await UpdateChecker.latest()
            UserDefaults.standard.set(Date(), forKey: lastUpdateCheckKey)
            if let latest, UpdateChecker.isNewer(latest.version, than: AppInfo.version) {
                update = latest
                updateStatus = "Version \(latest.version) is available."
            } else {
                update = nil
                if manual {
                    updateStatus = latest == nil
                        ? "No Mac release found (or GitHub couldn't be reached)."
                        : "You have the latest version."
                }
            }
        }
    }
}
