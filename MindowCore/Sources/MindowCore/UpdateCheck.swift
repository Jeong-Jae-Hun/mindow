import Foundation

/// A release number like `0.10.0`, compared field by field so 0.10.0 is newer than 0.9.1.
/// Only plain `major.minor.patch` parses: a tag with a suffix (`0.3.0-beta`), a fourth
/// field or a leading zero gives nil. The Homebrew cask this notice points to only
/// ships plain releases, and `MARKETING_VERSION` always has three fields.
public struct ReleaseVersion: Comparable, CustomStringConvertible, Sendable {
    public let fields: [Int]

    /// Accepts one leading `v` (`v0.2.0`, the tag form).
    public init?(_ string: String) {
        let number = string.hasPrefix("v") ? string.dropFirst() : Substring(string)
        let parts = number.split(separator: ".", omittingEmptySubsequences: false)
        // `Int("+1")` parses, so only ASCII digits get that far. Overflow still gives nil.
        guard parts.count == 3,
              parts.allSatisfy({ part in
                  !part.isEmpty && part.allSatisfy { $0.isASCII && $0.isNumber } && (part == "0" || !part.hasPrefix("0"))
              })
        else { return nil }
        let fields = parts.compactMap { Int($0) }
        guard fields.count == 3 else { return nil }
        self.fields = fields
    }

    public var description: String { fields.map(String.init).joined(separator: ".") }

    public static func < (lhs: ReleaseVersion, rhs: ReleaseVersion) -> Bool {
        lhs.fields.lexicographicallyPrecedes(rhs.fields)
    }
}

/// The part of GitHub's latest-release response the update notice uses.
/// https://docs.github.com/en/rest/releases/releases#get-the-latest-release
public struct LatestRelease: Equatable, Sendable {
    public let version: ReleaseVersion
    public let url: URL

    /// Nil for anything that isn't a usable published release: bad JSON, a draft or
    /// pre-release, a tag that isn't a plain version, or a page outside github.com
    /// (the menu opens this URL, so it can't point anywhere else).
    public init?(json data: Data) {
        guard let body = try? JSONDecoder().decode(Body.self, from: data),
              body.draft != true, body.prerelease != true,
              let version = ReleaseVersion(body.tagName),
              let url = URL(string: body.htmlURL), url.scheme == "https", url.host() == "github.com"
        else { return nil }
        self.version = version
        self.url = url
    }

    /// False when `current` doesn't parse, so a broken local version never shows a notice.
    public func isNewer(than current: String) -> Bool {
        ReleaseVersion(current).map { version > $0 } ?? false
    }

    private struct Body: Decodable {
        let tagName: String
        let htmlURL: String
        let draft: Bool?
        let prerelease: Bool?

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case draft, prerelease
        }
    }
}

public enum UpdateSchedule {
    public static let interval: TimeInterval = 24 * 60 * 60

    /// Due when never checked, a day has passed, or the last check is in the future
    /// (clock moved back), which would otherwise stop checks until that date.
    public static func isDue(lastCheck: Date?, now: Date) -> Bool {
        guard let lastCheck else { return true }
        let elapsed = now.timeIntervalSince(lastCheck)
        return elapsed >= interval || elapsed < 0
    }
}
