import XCTest
@testable import UsageCore

final class UsageCoreTests: XCTestCase {

    // MARK: Keychain service names

    func testDefaultDirUsesPlainServiceFirst() {
        let services = ClaudeCode.keychainServices(forDir: nil)
        XCTAssertEqual(services.first, "Claude Code-credentials")
    }

    func testCustomDirServiceIsSha256Prefix() {
        // sha256("/Users/test/.claude-work") starts with 03abf0ee
        XCTAssertEqual(ClaudeCode.hashedService(forConfigDir: "/Users/test/.claude-work"),
                       "Claude Code-credentials-03abf0ee")
        let services = ClaudeCode.keychainServices(forDir: "/Users/test/.claude-work/")
        XCTAssertEqual(services.first, "Claude Code-credentials-03abf0ee")
        XCTAssertFalse(services.contains("Claude Code-credentials"))
    }

    // MARK: Credentials

    func testParseCredentialsJSON() throws {
        let json = #"{"claudeAiOauth":{"accessToken":"sk-ant-oat01-abc","refreshToken":"r","expiresAt":1893456000000,"subscriptionType":"max","rateLimitTier":"default_claude_max_20x"}}"#
        let login = try XCTUnwrap(ClaudeCode.parseCredentials(Data(json.utf8)))
        XCTAssertEqual(login.token, "sk-ant-oat01-abc")
        XCTAssertEqual(login.plan, "Max 20x")
        XCTAssertEqual(login.expires, Date(timeIntervalSince1970: 1_893_456_000))
    }

    func testParseCredentialsHex() throws {
        let json = #"{"claudeAiOauth":{"accessToken":"tok","subscriptionType":"pro"}}"#
        let hex = Data(json.utf8).map { String(format: "%02x", $0) }.joined() + "\n"
        let login = try XCTUnwrap(ClaudeCode.parseCredentials(Data(hex.utf8)))
        XCTAssertEqual(login.token, "tok")
        XCTAssertEqual(login.plan, "Pro")
        XCTAssertNil(login.expires)
    }

    func testParseCredentialsRejectsJunk() {
        XCTAssertNil(ClaudeCode.parseCredentials(Data("".utf8)))
        XCTAssertNil(ClaudeCode.parseCredentials(Data("{}".utf8)))
        XCTAssertNil(ClaudeCode.parseCredentials(Data("not a secret".utf8)))
    }

    // MARK: Usage API

    func testParseUsageResponse() throws {
        let json = """
        {"five_hour":{"utilization":42.0,"resets_at":"2026-10-29T15:00:00.123456+00:00"},
         "seven_day":{"utilization":91,"resets_at":"2026-11-02T08:00:00Z"},
         "seven_day_opus":null,
         "limits":[{"kind":"weekly_scoped","percent":12.5,"resets_at":"2026-11-02T08:00:00+00:00",
                    "scope":{"model":{"display_name":"Claude Fable"}}}]}
        """
        guard case .usage(let w, let limited) = UsageClient.parseUsageResponse(status: 200, data: Data(json.utf8)) else {
            return XCTFail("expected usage")
        }
        XCTAssertFalse(limited)
        XCTAssertEqual(w[.fiveHour]?.pct, 42)
        XCTAssertEqual(w[.sevenDay]?.pct, 91)
        XCTAssertEqual(w[.fable]?.pct, 12.5)
        XCTAssertEqual(try XCTUnwrap(w[.fiveHour]?.reset).timeIntervalSince1970, 1_793_286_000, accuracy: 1)
        XCTAssertNotNil(w[.fable]?.reset)
    }

    func testUsageResponseErrors() {
        let scope = Data(#"{"error":{"type":"permission_error","message":"oauth_scope_insufficient"}}"#.utf8)
        XCTAssertEqual(UsageClient.parseUsageResponse(status: 403, data: scope), .noScope)
        XCTAssertEqual(UsageClient.parseUsageResponse(status: 401, data: Data()), .invalid(401))
        XCTAssertEqual(UsageClient.parseUsageResponse(status: 429, data: Data()), .retry(429))
    }

    // MARK: Probe

    func testParseProbeHeaders() {
        let headers = [
            "anthropic-ratelimit-unified-5h-utilization": "0.913",
            "anthropic-ratelimit-unified-5h-reset": "1793286000",
            "anthropic-ratelimit-unified-7d-utilization": "0.25",
            "anthropic-ratelimit-unified-7d_oi-utilization": "1.0",
            "anthropic-ratelimit-unified-status": "rejected",
        ]
        guard case .usage(let w, let limited) = UsageClient.parseProbe(status: 429, header: { headers[$0] }) else {
            return XCTFail("expected usage")
        }
        XCTAssertTrue(limited)
        XCTAssertEqual(w[.fiveHour]?.pct, 91.3)
        XCTAssertEqual(w[.fiveHour]?.reset, Date(timeIntervalSince1970: 1_793_286_000))
        XCTAssertEqual(w[.sevenDay]?.pct, 25)
        XCTAssertEqual(w[.fable]?.pct, 100)
    }

    func testProbeWithoutHeadersFails() {
        XCTAssertEqual(UsageClient.parseProbe(status: 400, header: { _ in nil }), .failed("HTTP 400, no usage headers"))
        XCTAssertEqual(UsageClient.parseProbe(status: 401, header: { _ in nil }), .invalid(401))
    }

    // MARK: Formatting and config

    func testCountdown() {
        let now = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(Format.countdown(to: now.addingTimeInterval(2 * 3600 + 14 * 60), now: now), "2h 14m")
        XCTAssertEqual(Format.countdown(to: now.addingTimeInterval(3 * 86400 + 4 * 3600), now: now), "3d 4h")
        XCTAssertEqual(Format.countdown(to: now.addingTimeInterval(30), now: now), "1m")
        XCTAssertEqual(Format.countdown(to: now.addingTimeInterval(-5), now: now), "now")
    }

    func testInitials() {
        XCTAssertEqual(Format.initials(for: ["me@work.com", "personal@x.com"]), ["M", "P"])
        XCTAssertEqual(Format.initials(for: ["paul@a.com", "pat@b.com"]), ["Pa", "Pa"])
        XCTAssertEqual(Format.initials(for: ["work", "home"]), ["W", "H"])
    }

    func testPlanFormat() {
        XCTAssertEqual(ClaudeCode.formatPlan(tier: "default_claude_max_5x", subscription: nil), "Max 5x")
        XCTAssertEqual(ClaudeCode.formatPlan(tier: nil, subscription: "claude_pro"), "Pro")
        XCTAssertNil(ClaudeCode.formatPlan(tier: nil, subscription: nil))
    }

    func testMergeAddsNewAccountsOnce() {
        var cfg = AppConfig()
        let found = [AccountConfig(name: "claude-code", label: "me@x.com"),
                     AccountConfig(name: "claude-code-work", label: "me@work.com", dir: "/Users/test/.claude-work")]
        XCTAssertEqual(ClaudeCode.merge(found, into: &cfg), 2)
        XCTAssertEqual(cfg.accounts.filter(\.isInMenuBar).map(\.name), ["claude-code"])
        XCTAssertEqual(ClaudeCode.merge(found, into: &cfg), 0)
    }

    // MARK: Full config

    private func usage(_ name: String, five: Double, seven: Double, reset: Date? = nil) -> AccountUsage {
        AccountUsage(name: name, label: name, status: .ok,
                     windows: [.fiveHour: UsageWindow(pct: five, reset: reset), .sevenDay: UsageWindow(pct: seven)])
    }

    func testMenuBarFallsBackToFirstVisibleAccount() {
        let cfg = AppConfig(accounts: [AccountConfig(name: "a", hidden: true), AccountConfig(name: "b"), AccountConfig(name: "c")])
        XCTAssertEqual(cfg.menuBarAccounts().map(\.name), ["b"])
    }

    func testHideAtLimitKeepsAtLeastOne() {
        var cfg = AppConfig(accounts: [AccountConfig(name: "a", menuBar: true), AccountConfig(name: "b", menuBar: true)])
        cfg.hideAtLimit = true
        let full = ["a": usage("a", five: 100, seven: 10), "b": usage("b", five: 20, seven: 10)]
        XCTAssertEqual(cfg.menuBarAccounts(usage: full).map(\.name), ["b"])
        let allFull = ["a": usage("a", five: 100, seven: 10), "b": usage("b", five: 5, seven: 100)]
        XCTAssertEqual(cfg.menuBarAccounts(usage: allFull).map(\.name), ["a", "b"])
    }

    func testWindowThatAlreadyResetReadsZero() {
        let now = Date(timeIntervalSince1970: 1000)
        let u = usage("a", five: 80, seven: 10, reset: Date(timeIntervalSince1970: 900))
        XCTAssertEqual(u.window(.fiveHour, now: now).pct, 0)
        XCTAssertEqual(u.window(.fiveHour).pct, 80)
    }

    func testModesDefaultsAndCaptions() {
        var cfg = AppConfig()
        XCTAssertEqual(cfg.insideMode, .percent)
        XCTAssertEqual(cfg.nextMode, NextMode.none)
        XCTAssertEqual(cfg.sizeMode, .compact)
        XCTAssertNil(cfg.namesMode)
        cfg.inside = "bogus"
        XCTAssertEqual(cfg.insideMode, .percent)
        cfg.captions = ["5h": "  Session ", "7d": " "]
        XCTAssertEqual(cfg.caption(.fiveHour), "Session")
        XCTAssertEqual(cfg.caption(.sevenDay), "7d")
        XCTAssertEqual(cfg.caption(.fable), "Fable")
    }

    func testPieKeyPrefersAccountChoice() {
        var cfg = AppConfig()
        cfg.innerWindow = "7d"
        XCTAssertEqual(cfg.pieKey(for: AccountConfig(name: "a")), .sevenDay)
        XCTAssertEqual(cfg.pieKey(for: AccountConfig(name: "a", pie: "5h")), .fiveHour)
    }

    func testInitialsUseShortFirst() {
        let cfg = AppConfig(accounts: [AccountConfig(name: "a", label: "Work", short: "Xyz"),
                                       AccountConfig(name: "b", label: "personal@x.com")])
        XCTAssertEqual(cfg.initials(), ["a": "Xy", "b": "P"])
    }

    func testUniqueName() {
        let cfg = AppConfig(accounts: [AccountConfig(name: "work")])
        XCTAssertEqual(cfg.uniqueName(from: "Work"), "work-2")
        XCTAssertEqual(cfg.uniqueName(from: "Me @ Home!"), "me-home")
        XCTAssertEqual(cfg.uniqueName(from: "!!!"), "account")
    }

    func testLimitKeysDefaultToFiveHourAndSevenDay() {
        XCTAssertEqual(AccountConfig(name: "a").limitKeys, [.fiveHour, .sevenDay])
        XCTAssertEqual(AccountConfig(name: "a", limits: ["fable", "5h"]).limitKeys, [.fiveHour, .fable])
    }

    func testSetupTokenShape() {
        XCTAssertTrue(TokenStore.looksLikeSetupToken("sk-ant-oat01-abc"))
        XCTAssertTrue(TokenStore.looksLikeSetupToken("  sk-ant-oat01-abc\n"))
        XCTAssertFalse(TokenStore.looksLikeSetupToken("sk-ant-api03-abc"))
    }

    func testResetFormats() {
        let now = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(Format.resetIn(now.addingTimeInterval(5400), now: now), "in 1h 30m")
        XCTAssertEqual(Format.resetIn(now.addingTimeInterval(-1), now: now), "")
        XCTAssertEqual(Format.resetIn(nil, now: now), "")
        XCTAssertEqual(Format.resetAt(now.addingTimeInterval(-1), now: now), "")
    }

    // MARK: Updates

    func testUpdateParsingPicksNewestMacRelease() throws {
        let json = """
        [{"tag_name":"v1.9.2","html_url":"https://example.com/w","draft":false,"prerelease":false,"body":""},
         {"tag_name":"mac-v1.2.0","html_url":"https://example.com/b","draft":false,"prerelease":true,"body":""},
         {"tag_name":"mac-v1.1.0","html_url":"https://example.com/a","draft":false,"prerelease":false,"body":"## Fixes\\n- one"},
         {"tag_name":"mac-v1.0.5","html_url":"https://example.com/c","draft":false,"prerelease":false,"body":""}]
        """
        let r = try XCTUnwrap(UpdateChecker.parse(Data(json.utf8)))
        XCTAssertEqual(r.version, "1.1.0")
        XCTAssertEqual(r.url.absoluteString, "https://example.com/a")
        XCTAssertEqual(UpdateChecker.shortNotes(r.notes), "Fixes\none")
    }

    func testVersionCompare() {
        XCTAssertTrue(UpdateChecker.isNewer("1.0.1", than: "1.0.0"))
        XCTAssertTrue(UpdateChecker.isNewer("1.10.0", than: "1.9.9"))
        XCTAssertFalse(UpdateChecker.isNewer("1.0.0", than: "1.0.0"))
        XCTAssertFalse(UpdateChecker.isNewer("0.9.0", than: "1.0.0"))
        XCTAssertFalse(UpdateChecker.isNewer("junk", than: "1.0.0"))
    }

    func testConfigRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ConfigStore(directory: dir)
        XCTAssertNil(try store.load())
        let cfg = AppConfig(refreshMinutes: 2, accounts: [AccountConfig(name: "a", menuBar: true, limits: ["5h", "bogus"])])
        try store.save(cfg)
        let back = try XCTUnwrap(try store.load())
        XCTAssertEqual(back, cfg)
        XCTAssertEqual(back.effectiveRefreshMinutes, 5)
        XCTAssertEqual(back.accounts[0].limitKeys, [.fiveHour])
    }
}
