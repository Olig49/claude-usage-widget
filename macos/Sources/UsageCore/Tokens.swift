import Foundation
import Security

/// Tokens the user pastes (from `claude setup-token`) are kept in this app's own generic
/// Keychain item: service "claude-usage-widget", account = the account's name. They are never
/// written to config.json or the log.
public enum TokenStore {
    public static let service = "claude-usage-widget"

    private static func query(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    public static func save(_ token: String, account: String) throws {
        let base = query(account)
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = Data(token.utf8)
        add[kSecAttrLabel as String] = "Claude Usage token (\(account))"
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw UsageError.keychain(message(status)) }
    }

    /// The token, or nil when there is none.
    public static func read(account: String) throws -> String? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = out as? Data else { throw UsageError.keychain(message(status)) }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func delete(account: String) {
        SecItemDelete(query(account) as CFDictionary)
    }

    private static func message(_ status: OSStatus) -> String {
        (SecCopyErrorMessageString(status, nil) as String?) ?? "error \(status)"
    }

    /// Setup tokens look like sk-ant-oat01-...
    public static func looksLikeSetupToken(_ s: String) -> Bool {
        s.trimmingCharacters(in: .whitespacesAndNewlines).range(of: #"^sk-ant-oat\d*-"#, options: .regularExpression) != nil
    }
}

/// A token ready for one refresh. Never logged or stored.
public struct ResolvedToken {
    public let token: String
    public let expires: Date?
    /// The plan as the login reports it (Claude Code logins only).
    public let plan: String?
}

public enum TokenSource {
    /// The account's token, or nil when it can't be found. Blocks (Keychain, commands): call off the main thread.
    public static func resolve(_ account: AccountConfig) throws -> ResolvedToken? {
        switch account.sourceKind {
        case .claudeCode?:
            guard let login = try ClaudeCode.login(dir: account.dir) else { return nil }
            return ResolvedToken(token: login.token, expires: login.expires, plan: login.plan)
        case .token?:
            guard let t = try TokenStore.read(account: account.name), !t.isEmpty else { return nil }
            return ResolvedToken(token: t, expires: nil, plan: nil)
        case .command?:
            guard let cmd = account.command, !cmd.trimmingCharacters(in: .whitespaces).isEmpty else {
                throw UsageError.command("No command set")
            }
            // A login shell, so the user's PATH (Homebrew, password manager CLIs) applies.
            let r = try Shell.run("/bin/zsh", ["-lc", cmd], timeout: 30)
            // Only stderr goes in messages: stdout is the token.
            if r.status != 0 { throw UsageError.command("exited \(r.status): \(r.stderrLastLine)") }
            let t = String(data: r.stdout, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if t.isEmpty { throw UsageError.command("printed nothing") }
            return ResolvedToken(token: t, expires: nil, plan: nil)
        case nil:
            throw UsageError.command("Unknown source '\(account.source)'")
        }
    }

    /// A short description of where the token comes from, for the Settings window.
    public static func describe(_ account: AccountConfig) -> String {
        switch account.sourceKind {
        case .claudeCode?:
            let dir = account.dir ?? "~/.claude"
            return "Claude Code login in \((dir as NSString).abbreviatingWithTildeInPath)"
        case .token?:
            return "Token saved in your Keychain"
        case .command?:
            return "Output of a command"
        case nil:
            return account.source
        }
    }
}
