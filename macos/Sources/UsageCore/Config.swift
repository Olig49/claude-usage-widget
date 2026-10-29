import Foundation

public enum AppInfo {
    public static let version = "1.0.0"
}

// MARK: Display choices (same names and values as the Windows widget's config.json)

/// What goes inside a ring.
public enum InsideMode: String, CaseIterable, Sendable {
    case none, initials, percent
    public var title: String {
        switch self {
        case .none: return "Nothing"
        case .initials: return "Initials"
        case .percent: return "Percentage"
        }
    }
}

/// What goes next to a ring.
public enum NextMode: String, CaseIterable, Sendable {
    case none, caption, percent, resetin, resetat
    public var title: String {
        switch self {
        case .none: return "Nothing"
        case .caption: return "Caption"
        case .percent: return "Percentage"
        case .resetin: return "Reset in"
        case .resetat: return "Reset day + time"
        }
    }
}

public enum SizeMode: String, CaseIterable, Sendable {
    case compact, normal, large
    public var title: String { rawValue.capitalized }
}

public enum SpacingMode: String, CaseIterable, Sendable {
    case tight, normal, wide
    public var title: String { rawValue.capitalized }
}

/// Where the account name goes. Nil in the config means automatic: left when more than one
/// account is in the menu bar, hidden for a single account.
public enum NamesMode: String, CaseIterable, Sendable {
    case left, right, hidden
    public var title: String { rawValue.capitalized }
}

public enum AccountStyle: String, CaseIterable, Sendable {
    case rings, combined
    public var title: String { rawValue.capitalized }
}

/// Where an account's token comes from.
public enum SourceKind: String, CaseIterable, Sendable {
    /// A Claude Code login (Keychain item or .credentials.json) for a config folder.
    case claudeCode = "claude-code"
    /// A `claude setup-token` token the user pasted, kept in this app's own Keychain item.
    case token
    /// Whatever a shell command prints (e.g. a password manager CLI).
    case command

    public var title: String {
        switch self {
        case .claudeCode: return "Claude Code login"
        case .token: return "Token (claude setup-token)"
        case .command: return "Command"
        }
    }
}

public enum PlanChoice {
    /// Offered in Settings; empty means Auto (whatever the API reports).
    public static let all = ["Pro", "Max 5x", "Max 20x"]
}

// MARK: Account

/// One account in config.json. Field names match the Windows widget where they overlap,
/// except `menuBar` (the Windows `taskbar`).
public struct AccountConfig: Codable, Equatable, Sendable {
    /// Stable id; also the Keychain account name for token accounts.
    public var name: String
    public var label: String?
    public var source: String
    /// Claude Code config folder; nil means ~/.claude.
    public var dir: String?
    /// For source "command".
    public var command: String?
    /// Show this account's rings in the menu bar.
    public var menuBar: Bool?
    /// Which rings to draw in the menu bar ("5h", "7d", "fable"). Nil = 5h and 7d.
    public var limits: [String]?
    /// 1-2 letters for "initials inside the ring".
    public var short: String?
    public var hidden: Bool?
    /// false skips the Fable probe for this account.
    public var fable: Bool?
    /// Plan label fallback when the API can't tell (token accounts). Nil/empty = Auto.
    public var plan: String?
    /// "rings" (default) or "combined".
    public var style: String?
    /// Combined dial: which limit goes in the middle ("5h" / "7d"); nil = the global choice.
    public var pie: String?

    public init(name: String, label: String? = nil, source: String = SourceKind.claudeCode.rawValue,
                dir: String? = nil, command: String? = nil, menuBar: Bool? = nil, limits: [String]? = nil,
                short: String? = nil, hidden: Bool? = nil, fable: Bool? = nil, plan: String? = nil,
                style: String? = nil, pie: String? = nil) {
        self.name = name
        self.label = label
        self.source = source
        self.dir = dir
        self.command = command
        self.menuBar = menuBar
        self.limits = limits
        self.short = short
        self.hidden = hidden
        self.fable = fable
        self.plan = plan
        self.style = style
        self.pie = pie
    }

    public var displayName: String { (label?.isEmpty == false ? label : nil) ?? name }
    public var isVisible: Bool { hidden != true }
    public var isInMenuBar: Bool { isVisible && menuBar == true }
    public var sourceKind: SourceKind? { SourceKind(rawValue: source) }

    public var styleMode: AccountStyle {
        get { style.flatMap(AccountStyle.init(rawValue:)) ?? .rings }
        set { style = newValue == .rings ? nil : newValue.rawValue }
    }

    /// The menu bar rings for the Rings style.
    public var limitKeys: [LimitKey] {
        guard let limits else { return [.fiveHour, .sevenDay] }
        let keys = LimitKey.allCases.filter { limits.contains($0.rawValue) }
        return keys.isEmpty ? [.fiveHour, .sevenDay] : keys
    }

    /// The short name shown in the menu bar next to the rings: the part of an email before the @, at most 14 characters.
    public var menuBarName: String {
        let base = displayName.split(separator: "@").first.map(String.init) ?? displayName
        return base.count > 14 ? String(base.prefix(13)) + "\u{2026}" : base
    }
}

// MARK: App config

public struct AppConfig: Codable, Equatable, Sendable {
    /// Minutes between refreshes; 5 at the lowest, 30 by default.
    public var refreshMinutes: Int?
    /// Renamed ring captions, keyed "5h", "7d", "fable".
    public var captions: [String: String]?
    public var inside: String?
    public var next: String?
    public var size: String?
    public var spacing: String?
    public var names: String?
    /// Inner (middle) limit of combined dials: "5h" (default) or "7d".
    public var innerWindow: String?
    /// Hide an account from the menu bar while a window is at 100%.
    public var hideAtLimit: Bool?
    /// Colour key under the account list.
    public var showLegend: Bool?
    /// A thin line between accounts in the menu bar.
    public var showDividers: Bool?
    /// Daily check for a newer release (default on).
    public var updateCheck: Bool?
    public var accounts: [AccountConfig]

    public init(refreshMinutes: Int? = 30, inside: String? = nil, accounts: [AccountConfig] = []) {
        self.refreshMinutes = refreshMinutes
        self.inside = inside
        self.accounts = accounts
    }

    public var effectiveRefreshMinutes: Int { max(5, refreshMinutes ?? 30) }

    public var insideMode: InsideMode {
        get { inside.flatMap(InsideMode.init(rawValue:)) ?? .percent }
        set { inside = newValue.rawValue }
    }
    /// Default is nothing next to the rings: menu bar space is tight on a laptop.
    public var nextMode: NextMode {
        get { next.flatMap(NextMode.init(rawValue:)) ?? .none }
        set { next = newValue.rawValue }
    }
    public var sizeMode: SizeMode {
        get { size.flatMap(SizeMode.init(rawValue:)) ?? .compact }
        set { size = newValue.rawValue }
    }
    public var spacingMode: SpacingMode {
        get { spacing.flatMap(SpacingMode.init(rawValue:)) ?? .normal }
        set { spacing = newValue.rawValue }
    }
    /// Nil = automatic.
    public var namesMode: NamesMode? {
        get { names.flatMap(NamesMode.init(rawValue:)) }
        set { names = newValue?.rawValue }
    }
    public var innerKey: LimitKey {
        get { innerWindow == LimitKey.sevenDay.rawValue ? .sevenDay : .fiveHour }
        set { innerWindow = newValue.rawValue }
    }
    public var updateCheckEnabled: Bool { updateCheck != false }

    /// The limit in the middle of an account's combined dial.
    public func pieKey(for account: AccountConfig) -> LimitKey {
        if account.pie == LimitKey.fiveHour.rawValue { return .fiveHour }
        if account.pie == LimitKey.sevenDay.rawValue { return .sevenDay }
        return innerKey
    }

    public func caption(_ key: LimitKey) -> String {
        let c = captions?[key.rawValue]?.trimmingCharacters(in: .whitespaces) ?? ""
        return c.isEmpty ? key.caption : c
    }

    public var visibleAccounts: [AccountConfig] { accounts.filter(\.isVisible) }

    /// Accounts in the menu bar: the ticked ones, or the first visible one when none is ticked.
    /// With hideAtLimit, accounts at a limit drop out unless that would leave nothing.
    public func menuBarAccounts(usage: [String: AccountUsage] = [:], now: Date = Date()) -> [AccountConfig] {
        let visible = visibleAccounts
        var shown = visible.filter { $0.menuBar == true }
        if shown.isEmpty, let first = visible.first { shown = [first] }
        guard hideAtLimit == true else { return shown }
        let ok = shown.filter { a in
            guard let u = usage[a.name] else { return true }
            return !u.isAtLimit(now: now)
        }
        return ok.isEmpty ? shown : ok
    }

    /// 1-2 letters per account: the account's own `short`, else the first letter of its name,
    /// two letters where first letters clash.
    public func initials() -> [String: String] {
        var out: [String: String] = [:]
        var auto: [AccountConfig] = []
        for a in accounts {
            let s = (a.short ?? "").trimmingCharacters(in: .whitespaces)
            if s.isEmpty { auto.append(a) } else { out[a.name] = String(s.prefix(2)) }
        }
        let made = Format.initials(for: auto.map(\.displayName))
        for (i, a) in auto.enumerated() { out[a.name] = made[i] }
        return out
    }

    /// A config-safe id for a new account, unique in this config.
    public func uniqueName(from label: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789-")
        var base = String(label.lowercased().map { allowed.contains($0) ? $0 : "-" })
        while base.contains("--") { base = base.replacingOccurrences(of: "--", with: "-") }
        base = base.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        if base.isEmpty { base = "account" }
        var name = base
        var n = 2
        while accounts.contains(where: { $0.name == name }) {
            name = "\(base)-\(n)"
            n += 1
        }
        return name
    }
}

// MARK: Storage

/// config.json and the log live in ~/Library/Application Support/claude-usage-widget.
public final class ConfigStore {
    public let directory: URL
    public var configURL: URL { directory.appendingPathComponent("config.json") }
    public var logURL: URL { directory.appendingPathComponent("widget.log") }

    public init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
            self.directory = base.appendingPathComponent("claude-usage-widget", isDirectory: true)
        }
    }

    public var exists: Bool { FileManager.default.fileExists(atPath: configURL.path) }

    /// nil when there is no config file yet. Throws when the file is there but unreadable.
    public func load() throws -> AppConfig? {
        guard exists else { return nil }
        let data = try Data(contentsOf: configURL)
        return try JSONDecoder().decode(AppConfig.self, from: data)
    }

    public func save(_ config: AppConfig) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys]
        let data = try enc.encode(config)
        try data.write(to: configURL, options: .atomic)
    }
}

public enum Log {
    private static let queue = DispatchQueue(label: "claude-usage-widget.log")
    public static var url: URL = ConfigStore().logURL

    /// Never pass a token here.
    public static func write(_ message: String) {
        let line = "\(stamp())  \(message)\n"
        queue.async {
            let fm = FileManager.default
            try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let h = try? FileHandle(forWritingTo: url) {
                h.seekToEndOfFile()
                h.write(Data(line.utf8))
                try? h.close()
            } else {
                try? Data(line.utf8).write(to: url)
            }
        }
    }

    private static func stamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: Date())
    }
}
