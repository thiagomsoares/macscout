import Foundation

/// Semantic app version (major.minor.patch). Used to compare the running
/// binary against GitHub Releases without pulling in a package manager.
public struct AppVersion: Comparable, Equatable, Hashable, CustomStringConvertible, Sendable {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// Parses `"1.2.3"`, `"v1.2.3"`, or `"1.2"` (patch defaults to 0).
    /// Extra pre-release / build suffixes (`-beta.1`, `+42`) are ignored.
    public init?(string raw: String) {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return nil }
        if s.first == "v" || s.first == "V" { s.removeFirst() }
        // Drop pre-release / build metadata.
        if let cut = s.firstIndex(where: { $0 == "-" || $0 == "+" }) {
            s = String(s[..<cut])
        }
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2, parts.count <= 3,
              let major = Int(parts[0]),
              let minor = Int(parts[1]) else { return nil }
        let patch = parts.count == 3 ? (Int(parts[2]) ?? -1) : 0
        guard patch >= 0 else { return nil }
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public var description: String { "\(major).\(minor).\(patch)" }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }
}
