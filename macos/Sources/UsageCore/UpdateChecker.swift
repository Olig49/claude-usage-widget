import Foundation

public struct ReleaseInfo: Equatable, Sendable {
    public let version: String
    public let url: URL
    public let notes: String
}

/// Looks for a newer Mac release on GitHub. Mac releases are tagged "mac-v<version>" so they
/// don't mix with the Windows widget's "v<version>" tags in the same repo. It only checks and
/// links to the release page; it never downloads or installs anything.
public enum UpdateChecker {
    public static let repo = "Olig49/claude-usage-widget"
    public static let tagPrefix = "mac-v"

    public static var releasesPage: URL { URL(string: "https://github.com/\(repo)/releases")! }

    /// The newest Mac release, or nil when offline, rate-limited or there is none.
    public static func latest() async -> ReleaseInfo? {
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases?per_page=30") else { return nil }
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("claude-usage-widget-mac/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 10
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return parse(data)
        } catch {
            return nil
        }
    }

    public static func parse(_ data: Data) -> ReleaseInfo? {
        guard let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
        var best: ReleaseInfo?
        for r in list {
            if r["draft"] as? Bool == true || r["prerelease"] as? Bool == true { continue }
            guard let tag = r["tag_name"] as? String, tag.hasPrefix(tagPrefix),
                  let page = (r["html_url"] as? String).flatMap(URL.init(string:)) else { continue }
            let version = String(tag.dropFirst(tagPrefix.count))
            guard parts(version) != nil else { continue }
            if let b = best, !isNewer(version, than: b.version) { continue }
            best = ReleaseInfo(version: version, url: page, notes: (r["body"] as? String) ?? "")
        }
        return best
    }

    static func parts(_ v: String) -> [Int]? {
        let p = v.split(separator: ".").map { Int($0) }
        guard p.count == 3, p.allSatisfy({ $0 != nil }) else { return nil }
        return p.compactMap { $0 }
    }

    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        guard let a = parts(candidate), let b = parts(current) else { return false }
        return a.lexicographicallyPrecedes(b) == false && a != b
    }

    /// The first few lines of release notes with markdown marks stripped.
    public static func shortNotes(_ body: String, lines: Int = 3) -> String {
        let cleaned = body.split(whereSeparator: \.isNewline).map { line -> String in
            var s = String(line)
            s = s.replacingOccurrences(of: #"^[\s#>*\-]+"#, with: "", options: .regularExpression)
            s = s.replacingOccurrences(of: "`", with: "").replacingOccurrences(of: "*", with: "")
            return s.trimmingCharacters(in: .whitespaces)
        }.filter { !$0.isEmpty }
        return cleaned.prefix(lines).joined(separator: "\n")
    }
}
