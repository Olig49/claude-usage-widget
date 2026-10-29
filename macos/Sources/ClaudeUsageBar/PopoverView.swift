import SwiftUI
import UsageCore

/// Actions the dropdown's buttons call (the same ones as the right-click menu).
struct PopoverActions {
    var refresh: () -> Void
    var scan: () -> Void
    var settings: () -> Void
    var openConfig: () -> Void
    var openLog: () -> Void
    var openUpdate: () -> Void
    var quit: () -> Void
}

/// The dropdown: every account with its 5h / 7d / Fable usage and reset countdowns.
@MainActor
struct PopoverView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var loginItem: LoginItem
    let actions: PopoverActions

    var body: some View {
        // Re-render every 30 s so countdowns and "updated" stay current while it's open.
        TimelineView(.periodic(from: .now, by: 30)) { context in
            content(now: context.date)
        }
        .padding(14)
        .frame(width: 340)
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        let cfg = store.effective
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Claude usage").font(.headline)
                Spacer()
                if store.refreshing || store.scanning {
                    ProgressView().controlSize(.small)
                }
            }

            if let update = store.update {
                Button(action: actions.openUpdate) {
                    Label("Version \(update.version) is available", systemImage: "arrow.down.circle")
                        .font(.callout)
                }
                .buttonStyle(.link)
            }

            let accounts = store.visibleAccounts
            if accounts.isEmpty {
                Text(store.scanning
                     ? "Looking for Claude Code logins\u{2026}"
                     : "No accounts yet. Sign in with claude in Terminal and choose Scan for accounts, or add a token in Settings.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // A scroll view only when the list is long, so short lists size the popover to fit.
            if accounts.count > 4 {
                ScrollView {
                    accountList(accounts, config: cfg, now: now).padding(.trailing, 6)
                }
                .frame(height: 460)
            } else {
                accountList(accounts, config: cfg, now: now)
            }

            if cfg.showLegend == true {
                LegendView()
            }

            if let notice = store.notice {
                Text(notice).font(.caption).foregroundStyle(.secondary)
            }

            Divider()

            HStack(spacing: 10) {
                Text(updatedText(now: now, config: cfg))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: actions.refresh) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(store.refreshing || !store.canRefreshManually(now: now))
                .help("Refresh now (at most once a minute)")

                Button(action: actions.settings) {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(",", modifiers: .command)
                .help("Settings")

                Menu {
                    Button("Settings\u{2026}", action: actions.settings)
                    Button("Scan for accounts", action: actions.scan)
                    Toggle("Launch at login", isOn: Binding(
                        get: { loginItem.isEnabled },
                        set: { loginItem.setEnabled($0) }
                    ))
                    Divider()
                    Button("Open config file\u{2026}", action: actions.openConfig)
                    Button("Open log", action: actions.openLog)
                    Divider()
                    Button("Quit Claude Usage", action: actions.quit)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("More")
            }
        }
    }

    @ViewBuilder
    private func accountList(_ accounts: [AccountConfig], config: AppConfig, now: Date) -> some View {
        let shown = Set(store.menuBarAccounts(now: now).map(\.name))
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(accounts.enumerated()), id: \.element.name) { index, account in
                if index > 0 { Divider() }
                AccountCard(account: account, usage: store.usage[account.name], config: config, now: now,
                            inMenuBar: shown.contains(account.name)) { on in
                    store.setInMenuBar(account.name, on)
                }
            }
        }
    }

    private func updatedText(now: Date, config: AppConfig) -> String {
        if store.refreshing { return "Refreshing\u{2026}" }
        guard let last = store.lastRefresh else { return "Not updated yet" }
        let mins = Int(now.timeIntervalSince(last) / 60)
        let ago = mins < 1 ? "just now" : (mins < 60 ? "\(mins) min ago" : "\(mins / 60) h ago")
        return "Updated \(ago) \u{00B7} every \(config.effectiveRefreshMinutes) min"
    }
}

@MainActor
private struct AccountCard: View {
    let account: AccountConfig
    let usage: AccountUsage?
    let config: AppConfig
    let now: Date
    /// Shown in the menu bar right now (ticked, or the first account when none is ticked).
    let inMenuBar: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Toggle(isOn: Binding(get: { account.menuBar == true }, set: onToggle)) {
                    Text(account.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .toggleStyle(.checkbox)
                .help(inMenuBar && account.menuBar != true
                      ? "Shown in the menu bar because no account is ticked"
                      : "Show in the menu bar")

                Spacer(minLength: 4)

                if let plan = usage?.plan ?? account.plan, !plan.isEmpty {
                    Text(plan)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.secondary.opacity(0.15)))
                }
            }

            if let u = usage {
                if u.status.isProblem || u.windows.isEmpty {
                    Label(u.error ?? "No usage data", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(LimitKey.allCases, id: \.self) { key in
                        let w = u.window(key, now: now)
                        if let pct = w.pct {
                            LimitRow(caption: config.caption(key), longName: key.longName, pct: pct, reset: w.reset, now: now)
                        }
                    }
                    if u.isAtLimit(now: now) {
                        Text("At the limit").font(.caption).foregroundStyle(.red)
                    }
                }
            } else {
                Text("Loading\u{2026}").font(.caption).foregroundStyle(.secondary)
            }
        }
        .help(helpText)
    }

    private var helpText: String {
        guard let u = usage, let method = u.method else { return TokenSource.describe(account) }
        let how = method == "usage-api"
            ? "Read with the free usage API"
            : "Read with a 1-token probe (this token can't use the usage API)"
        return "\(TokenSource.describe(account))\n\(how)"
    }
}

@MainActor
private struct LimitRow: View {
    let caption: String
    let longName: String
    let pct: Double
    let reset: Date?
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text(caption)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .frame(width: 44, alignment: .leading)
                UsageBar(fraction: pct / 100, color: barColor)
                Text(Format.percent(pct))
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .frame(width: 38, alignment: .trailing)
            }
            if let reset {
                Text(Format.resetLine(reset, now: now))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 52)
            }
        }
        .help(longName)
    }

    private var barColor: Color { severityColor(pct) }
}

func severityColor(_ pct: Double) -> Color {
    switch Severity(pct: pct) {
    case .ok: return .green
    case .warn: return .orange
    case .high: return .red
    }
}

@MainActor
private struct UsageBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.2))
                Capsule().fill(color).frame(width: geo.size.width * CGFloat(min(max(fraction, 0), 1)))
            }
        }
        .frame(height: 6)
    }
}

/// The colour key under the list (Display > Show legend).
@MainActor
struct LegendView: View {
    var body: some View {
        HStack(spacing: 12) {
            item(.green, "under 70%")
            item(.orange, "70\u{2013}89%")
            item(.red, "90% +")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private func item(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text)
        }
    }
}
