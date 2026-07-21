import Foundation

/// A published GitHub Release, decoded from the Releases REST API.
public struct GitHubRelease: Decodable, Sendable, Equatable {
    public let tagName: String
    public let name: String?
    public let htmlURL: String
    public let body: String?
    public let prerelease: Bool
    public let draft: Bool
    public let publishedAt: Date?
    public let assets: [Asset]

    public struct Asset: Decodable, Sendable, Equatable {
        public let name: String
        public let browserDownloadURL: String
        public let size: Int
        public let contentType: String?

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
            case size
            case contentType = "content_type"
        }
    }

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case htmlURL = "html_url"
        case body
        case prerelease, draft
        case publishedAt = "published_at"
        case assets
    }

    /// Semantic version parsed from `tag_name`, if well-formed.
    public var version: AppVersion? { AppVersion(string: tagName) }

    /// Prefer a `.dmg` asset (Macscout ships drag-to-install DMGs).
    public var dmgAsset: Asset? {
        assets.first { $0.name.lowercased().hasSuffix(".dmg") }
    }

    public var dmgURL: URL? {
        guard let asset = dmgAsset else { return nil }
        return URL(string: asset.browserDownloadURL)
    }
}

/// Fetches the latest non-draft release for the Macscout GitHub repo.
/// Pure HTTPS + Foundation — no Sparkle, no third-party updater.
public enum GitHubReleaseClient {
    public static let defaultLatestURL = URL(
        string: "https://api.github.com/repos/thiagomsoares/macscout/releases/latest"
    )!

    public enum ClientError: Error, Equatable, LocalizedError {
        case httpStatus(Int)
        case decoding
        case noRelease

        public var errorDescription: String? {
            switch self {
            case .httpStatus(let code): return "GitHub returned HTTP \(code)."
            case .decoding: return "Unexpected release response format."
            case .noRelease: return "No published release found."
            }
        }
    }

    /// Decodes a release payload (exposed for tests).
    public static func decodeRelease(from data: Data,
                                     decoder: JSONDecoder = makeDecoder()) throws -> GitHubRelease {
        do {
            return try decoder.decode(GitHubRelease.self, from: data)
        } catch {
            throw ClientError.decoding
        }
    }

    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// GETs `releases/latest`. Pass a custom `session`/`url` in tests.
    public static func fetchLatest(
        url: URL = defaultLatestURL,
        session: URLSession = .shared,
        userAgent: String = "Macscout"
    ) async throws -> GitHubRelease {
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse {
            guard (200..<300).contains(http.statusCode) else {
                throw ClientError.httpStatus(http.statusCode)
            }
        }
        let release = try decodeRelease(from: data)
        if release.draft { throw ClientError.noRelease }
        return release
    }
}
