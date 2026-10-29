import AppKit
import SwiftUI
import UsageCore

// MARK: Binding helpers

extension Binding where Value == String? {
    /// An empty string stands for nil.
    func orEmpty() -> Binding<String> {
        Binding<String>(get: { self.wrappedValue ?? "" }, set: { self.wrappedValue = $0.isEmpty ? nil : $0 })
    }
}

extension Binding where Value == Bool? {
    func or(_ fallback: Bool) -> Binding<Bool> {
        Binding<Bool>(get: { self.wrappedValue ?? fallback }, set: { self.wrappedValue = $0 })
    }
}

extension UsageStore {
    /// The Settings draft as a binding (the saved config until the first edit).
    var editing: Binding<AppConfig> {
        Binding(get: { self.draft ?? self.config }, set: { self.draft = $0 })
    }

    func accountBinding(_ name: String) -> Binding<AccountConfig> {
        Binding(
            get: { self.effective.accounts.first { $0.name == name } ?? AccountConfig(name: name) },
            set: { new in
                var c = self.effective
                guard let i = c.accounts.firstIndex(where: { $0.name == name }) else { return }
                c.accounts[i] = new
                self.draft = c
            }
        )
    }
}

/// Lets the user pick a Claude Code config folder (hidden folders shown, starting in the home folder).
@MainActor
func chooseClaudeFolder() -> String? {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.showsHiddenFiles = true
    panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
    panel.message = "Choose the Claude Code config folder for this account (e.g. .claude-work)"
    panel.prompt = "Choose"
    guard panel.runModal() == .OK, let url = panel.url else { return nil }
    return ClaudeCode.normalize(url.path)
}

private func tilde(_ path: String) -> String { (path as NSString).abbreviatingWithTildeInPath }

// MARK: Window content

@MainActor
struct SettingsView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var loginItem: LoginItem
    let onOK: () -> Void
    let onCancel: () -> Void
    let onApply: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            TabView {
                AccountsTab(store: store)
                    .tabItem { Text("Accounts") }
                DisplayTab(store: store, loginItem: loginItem)
                    .tabItem { Text("Display") }
                CaptionsTab(store: store)
                    .tabItem { Text("Captions") }
                UpdatesTab(store: store)
                    .tabItem { Text("Updates") }
            }
            .padding([.top, .horizontal], 16)

            HStack {
                Text("Changes show in the menu bar right away. OK or Apply keeps them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Apply", action: onApply)
                    .disabled(!store.hasUnsavedChanges)
                Button("OK", action: onOK)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(minWidth: 620, minHeight: 480)
    }
}

// MARK: Accounts

@MainActor
private struct AccountsTab: View {
    @ObservedObject var store: UsageStore
    @State private var selection: String?
    @State private var showAdd = false
    @State private var showFind = false
    @State private var confirmRemove = false

    private var accounts: [AccountConfig] { store.effective.accounts }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                List(selection: $selection) {
                    ForEach(accounts, id: \.name) { a in
                        HStack(spacing: 6) {
                            Text(a.displayName).lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 2)
                            if a.hidden == true {
                                Image(systemName: "eye.slash").foregroundStyle(.secondary)
                            } else if a.isInMenuBar {
                                Image(systemName: "menubar.rectangle").foregroundStyle(.secondary)
                            }
                        }
                        .tag(a.name)
                    }
                }
                .frame(width: 220)

                HStack(spacing: 6) {
                    Menu {
                        Button("Add account\u{2026}") { showAdd = true }
                        Button("Find new Claude Code logins\u{2026}") { showFind = true }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Add an account")

                    Button { confirmRemove = true } label: { Image(systemName: "minus") }
                        .disabled(selection == nil)
                        .help("Remove the selected account")
                    Spacer()
                    Button { move(-1) } label: { Image(systemName: "chevron.up") }
                        .disabled(!canMove(-1))
                        .help("Move up")
                    Button { move(1) } label: { Image(systemName: "chevron.down") }
                        .disabled(!canMove(1))
                        .help("Move down")
                }
                .buttonStyle(.borderless)
            }

            if let name = selection, accounts.contains(where: { $0.name == name }) {
                AccountDetail(store: store, account: store.accountBinding(name), config: store.editing)
                    .id(name)
            } else {
                VStack(spacing: 8) {
                    Spacer()
                    Text(accounts.isEmpty ? "No accounts yet." : "Select an account.")
                        .foregroundStyle(.secondary)
                    if accounts.isEmpty {
                        Button("Add account\u{2026}") { showAdd = true }
                        Button("Find Claude Code logins\u{2026}") { showFind = true }
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 8)
        .onAppear {
            if selection == nil { selection = accounts.first?.name }
        }
        .sheet(isPresented: $showAdd) {
            AddAccountView(store: store) { name in selection = name }
        }
        .sheet(isPresented: $showFind) {
            FindAccountsView(store: store)
        }
        .confirmationDialog(removeTitle, isPresented: $confirmRemove) {
            Button("Remove", role: .destructive) { remove() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(removeMessage)
        }
    }

    private var selected: AccountConfig? { accounts.first { $0.name == selection } }
    private var removeTitle: String { "Remove \(selected?.displayName ?? "this account")?" }
    private var removeMessage: String {
        selected?.sourceKind == .token
            ? "Its token is deleted from your Keychain when you press OK or Apply."
            : "It's only removed from the widget; the Claude Code login itself isn't touched."
    }

    private func index() -> Int? { accounts.firstIndex { $0.name == selection } }

    private func canMove(_ delta: Int) -> Bool {
        guard let i = index() else { return false }
        return accounts.indices.contains(i + delta)
    }

    private func move(_ delta: Int) {
        guard let i = index(), accounts.indices.contains(i + delta) else { return }
        var c = store.effective
        c.accounts.swapAt(i, i + delta)
        store.draft = c
    }

    private func remove() {
        guard let i = index() else { return }
        var c = store.effective
        c.accounts.remove(at: i)
        store.draft = c
        selection = c.accounts.indices.contains(i) ? c.accounts[i].name : c.accounts.last?.name
    }
}

@MainActor
private struct AccountDetail: View {
    @ObservedObject var store: UsageStore
    @Binding var account: AccountConfig
    let config: Binding<AppConfig>
    @State private var newToken = ""
    @State private var tokenMessage: String?

    var body: some View {
        let cfg = config.wrappedValue
        Form {
            Section {
                TextField("Name", text: $account.label.orEmpty(), prompt: Text(account.name))
                TextField("Initials", text: initialsBinding, prompt: Text(cfg.initials()[account.name] ?? ""))
                Toggle("Show in the menu bar", isOn: $account.menuBar.or(false))
                Toggle("Hide this account everywhere", isOn: $account.hidden.or(false))
            }

            Section("Menu bar") {
                Picker("Style", selection: $account.styleMode) {
                    ForEach(AccountStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                if account.styleMode == .rings {
                    LabeledContent("Rings") {
                        HStack(spacing: 12) {
                            ForEach(LimitKey.allCases, id: \.self) { k in
                                Toggle(cfg.caption(k), isOn: limitBinding(k)).toggleStyle(.checkbox)
                            }
                        }
                    }
                } else {
                    Picker("Middle of the dial", selection: pieBinding) {
                        Text("Default (\(cfg.caption(cfg.innerKey)))").tag("")
                        Text(cfg.caption(.fiveHour)).tag(LimitKey.fiveHour.rawValue)
                        Text(cfg.caption(.sevenDay)).tag(LimitKey.sevenDay.rawValue)
                    }
                    Text("The middle limit is a pie when percentages are inside the rings, otherwise an inner ring (with the initials in the centre). The outer ring is the other window.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Account") {
                LabeledContent("Source", value: TokenSource.describe(account))
                switch account.sourceKind {
                case .claudeCode?:
                    LabeledContent("Folder") {
                        HStack {
                            Text(tilde(account.dir ?? ClaudeCode.defaultDir.path)).lineLimit(1).truncationMode(.middle)
                            Button("Choose\u{2026}") {
                                if let path = chooseClaudeFolder() {
                                    account.dir = ClaudeCode.isDefault(path) ? nil : path
                                }
                            }
                        }
                    }
                case .token?:
                    HStack {
                        SecureField("Replace token", text: $newToken, prompt: Text("Paste a new token"))
                        Button("Replace") { replaceToken() }
                            .disabled(newToken.isEmpty)
                    }
                    if let tokenMessage {
                        Text(tokenMessage).font(.caption).foregroundStyle(.secondary)
                    }
                case .command?:
                    TextField("Command", text: $account.command.orEmpty(), prompt: Text("op read op://Private/claude/token"))
                case nil:
                    EmptyView()
                }
                Picker("Plan", selection: $account.plan.orEmpty()) {
                    Text("Auto").tag("")
                    ForEach(PlanChoice.all, id: \.self) { Text($0).tag($0) }
                }
                .help("Used when Anthropic doesn't report the plan (setup tokens). The reported plan always wins.")
                Toggle("Check the Fable weekly limit", isOn: $account.fable.or(true))
                    .help("For tokens that can't use the usage API, the Fable limit needs a tiny Fable request (about 35 tokens).")
            }

            if let u = store.usage[account.name], let err = u.error, u.status.isProblem {
                Section("Status") {
                    Label(err, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var initialsBinding: Binding<String> {
        Binding(
            get: { account.short ?? "" },
            set: { v in
                let t = String(v.trimmingCharacters(in: .whitespaces).prefix(2))
                account.short = t.isEmpty ? nil : t
            }
        )
    }

    private var pieBinding: Binding<String> {
        Binding(get: { account.pie ?? "" }, set: { account.pie = $0.isEmpty ? nil : $0 })
    }

    /// One ring on or off; the last one can't be turned off.
    private func limitBinding(_ key: LimitKey) -> Binding<Bool> {
        Binding(
            get: { account.limitKeys.contains(key) },
            set: { on in
                var keys = Set(account.limitKeys)
                if on { keys.insert(key) } else { keys.remove(key) }
                guard !keys.isEmpty else { return }
                account.limits = LimitKey.allCases.filter { keys.contains($0) }.map(\.rawValue)
            }
        )
    }

    private func replaceToken() {
        let t = newToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard TokenStore.looksLikeSetupToken(t) else {
            tokenMessage = "That doesn't look like a setup token (it starts with sk-ant-oat)."
            return
        }
        do {
            try store.replaceToken(for: account.name, with: t)
            newToken = ""
            tokenMessage = "Token replaced."
        } catch {
            tokenMessage = "Couldn't save the token: \(error)"
        }
    }
}

// MARK: Add / find accounts

@MainActor
private struct AddAccountView: View {
    @ObservedObject var store: UsageStore
    let onAdded: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var label = ""
    @State private var kind: SourceKind = .token
    @State private var token = ""
    @State private var command = ""
    @State private var dir: String?
    @State private var plan = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add account").font(.title3.weight(.semibold))
            Form {
                TextField("Name", text: $label, prompt: Text("e.g. Work"))
                Picker("Source", selection: $kind) {
                    ForEach(SourceKind.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                switch kind {
                case .token:
                    SecureField("Token", text: $token, prompt: Text("sk-ant-oat01-\u{2026}"))
                    Text("In Terminal, run claude setup-token, sign in with this account and paste the token it prints. It's kept in your Mac's Keychain, never in the config file. Setup tokens can't use the free usage API, so each refresh costs about 35 tokens.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                case .claudeCode:
                    LabeledContent("Folder") {
                        HStack {
                            Text(dir.map(tilde) ?? "None chosen")
                                .foregroundStyle(dir == nil ? Color.secondary : Color.primary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Button("Choose\u{2026}") { dir = chooseClaudeFolder() }
                        }
                    }
                    Text("The account's Claude Code config folder, e.g. ~/.claude-work. To create one, run CLAUDE_CONFIG_DIR=~/.claude-work claude in Terminal and sign in with /login.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                case .command:
                    TextField("Command", text: $command, prompt: Text("op read op://Private/claude/token"))
                    Text("Runs in your login shell; whatever it prints is used as the token.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Picker("Plan", selection: $plan) {
                    Text("Auto").tag("")
                    ForEach(PlanChoice.all, id: \.self) { Text($0).tag($0) }
                }
            }
            .formStyle(.grouped)

            if let error {
                Text(error).font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add") { add() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isComplete)
            }
        }
        .padding(20)
        .frame(width: 500)
    }

    private var isComplete: Bool {
        switch kind {
        case .token: return !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .claudeCode: return dir != nil
        case .command: return !command.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    private func add() {
        error = nil
        var lbl = label.trimmingCharacters(in: .whitespaces)
        var a = AccountConfig(name: "", source: kind.rawValue)
        a.plan = plan.isEmpty ? nil : plan
        switch kind {
        case .token:
            guard TokenStore.looksLikeSetupToken(token) else {
                error = "That doesn't look like a setup token. It starts with sk-ant-oat; run claude setup-token to get one."
                return
            }
        case .claudeCode:
            guard let dir else { return }
            let isDefault = ClaudeCode.isDefault(dir)
            let taken = store.effective.accounts.contains { c in
                c.sourceKind == .claudeCode && ClaudeCode.isDefault(c.dir) == isDefault
                    && (isDefault || ClaudeCode.normalize(c.dir ?? "") == dir)
            }
            if taken {
                error = "That login is already in the list."
                return
            }
            a.dir = isDefault ? nil : dir
            if lbl.isEmpty { lbl = ClaudeCode.identity(dir: dir)?.email ?? URL(fileURLWithPath: dir).lastPathComponent }
        case .command:
            a.command = command.trimmingCharacters(in: .whitespaces)
        }
        if lbl.isEmpty { lbl = kind == .token ? "Token" : "Account" }
        a.label = lbl
        a.name = store.uniqueName(from: lbl)
        do {
            try store.addAccount(a, token: kind == .token ? token : nil)
            onAdded(a.name)
            dismiss()
        } catch {
            self.error = "Couldn't add the account: \(error)"
        }
    }
}

@MainActor
private struct FindAccountsView: View {
    @ObservedObject var store: UsageStore
    @Environment(\.dismiss) private var dismiss
    @State private var found: [AccountConfig]?
    @State private var added = Set<String>()
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Find new accounts").font(.title3.weight(.semibold))
            if let found {
                if found.isEmpty {
                    Text("No new Claude Code logins on this Mac.").foregroundStyle(.secondary)
                } else {
                    ForEach(found, id: \.name) { a in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(a.displayName)
                                Text(TokenSource.describe(a)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if added.contains(a.name) {
                                Text("Added").foregroundStyle(.secondary)
                            } else {
                                Button("Add") { add(a) }
                            }
                        }
                    }
                }
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Looking for Claude Code logins\u{2026}")
                }
            }
            if let error { Text(error).font(.callout).foregroundStyle(.red) }
            Text("Each login lives in its own ~/.claude* folder. To add another account, run CLAUDE_CONFIG_DIR=~/.claude-work claude in Terminal, sign in with /login, then look again.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
        .task { found = await store.findNewLogins() }
    }

    private func add(_ a: AccountConfig) {
        do {
            try store.addAccount(a, token: nil)
            added.insert(a.name)
        } catch {
            self.error = "\(error)"
        }
    }
}

// MARK: Display

@MainActor
private struct DisplayTab: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var loginItem: LoginItem

    var body: some View {
        let cfg = store.editing
        Form {
            Section("Menu bar") {
                Picker("Inside the ring", selection: cfg.insideMode) {
                    ForEach(InsideMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("Next to the ring", selection: cfg.nextMode) {
                    ForEach(NextMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("Size", selection: cfg.sizeMode) {
                    ForEach(SizeMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .help("Large also shows when each limit resets, under the caption or percentage.")
                Picker("Spacing", selection: cfg.spacingMode) {
                    ForEach(SpacingMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("Account names", selection: Binding(
                    get: { cfg.wrappedValue.names ?? "" },
                    set: { cfg.wrappedValue.names = $0.isEmpty ? nil : $0 }
                )) {
                    Text("Automatic").tag("")
                    ForEach(NamesMode.allCases, id: \.self) { Text($0.title).tag($0.rawValue) }
                }
                .help("Automatic shows names on the left when more than one account is in the menu bar.")
                Picker("Middle of combined dials", selection: cfg.innerKey) {
                    Text(cfg.wrappedValue.caption(.fiveHour)).tag(LimitKey.fiveHour)
                    Text(cfg.wrappedValue.caption(.sevenDay)).tag(LimitKey.sevenDay)
                }
                Toggle("Line between accounts", isOn: cfg.showDividers.or(false))
                Toggle("Hide an account while it's at its limit", isOn: cfg.hideAtLimit.or(false))
                    .help("Unless that would leave nothing in the menu bar.")
            }
            Section("Account list") {
                Toggle("Show the colour key", isOn: cfg.showLegend.or(false))
            }
            Section("General") {
                Stepper(value: Binding(
                    get: { cfg.wrappedValue.effectiveRefreshMinutes },
                    set: { cfg.wrappedValue.refreshMinutes = max(5, $0) }
                ), in: 5...240, step: 5) {
                    Text("Refresh every \(cfg.wrappedValue.effectiveRefreshMinutes) minutes")
                }
                Toggle("Launch at login", isOn: Binding(get: { loginItem.isEnabled }, set: { loginItem.setEnabled($0) }))
                    .help("Applies right away.")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: Captions

@MainActor
private struct CaptionsTab: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        Form {
            Section {
                ForEach(LimitKey.allCases, id: \.self) { key in
                    TextField(key.longName, text: binding(key), prompt: Text(key.caption))
                }
            } header: {
                Text("Ring captions")
            } footer: {
                Text("Shown next to the rings (Display > Next to the ring > Caption), in the account list and in tooltips. Leave a field empty for the default.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button("Reset to defaults") {
                store.editing.wrappedValue.captions = nil
            }
        }
        .formStyle(.grouped)
    }

    private func binding(_ key: LimitKey) -> Binding<String> {
        Binding(
            get: { store.editing.wrappedValue.captions?[key.rawValue] ?? "" },
            set: { v in
                var c = store.editing.wrappedValue.captions ?? [:]
                let t = String(v.prefix(10))
                c[key.rawValue] = t.isEmpty ? nil : t
                store.editing.wrappedValue.captions = c.isEmpty ? nil : c
            }
        )
    }
}

// MARK: Updates

@MainActor
private struct UpdatesTab: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        Form {
            Section {
                LabeledContent("Installed version", value: AppInfo.version)
                Toggle("Check for updates once a day", isOn: store.editing.updateCheck.or(true))
                HStack {
                    Button("Check now") { store.checkForUpdates(manual: true) }
                    if let status = store.updateStatus {
                        Text(status).foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text("Mac releases are published on github.com/\(UpdateChecker.repo) with tags starting \(UpdateChecker.tagPrefix). The app only checks and links to the release; it never downloads anything by itself.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let update = store.update {
                Section("Version \(update.version)") {
                    let notes = UpdateChecker.shortNotes(update.notes)
                    if !notes.isEmpty { Text(notes).font(.callout) }
                    Button("Open the download page") { NSWorkspace.shared.open(update.url) }
                }
            }
        }
        .formStyle(.grouped)
    }
}
