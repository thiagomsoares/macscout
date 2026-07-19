import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

/// Errors surfaced by `NightscoutClient`.
public enum NightscoutError: Error, Equatable, LocalizedError {
    case invalidURL
    case unauthorized
    case httpError(Int)
    case decoding(String)
    case network(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid Nightscout URL."
        case .unauthorized: return "Unauthorized — check token / api-secret."
        case .httpError(let code): return "Server returned HTTP \(code)."
        case .decoding(let detail): return "Unexpected response format (\(detail))."
        case .network(let detail): return detail
        }
    }
}

/// Async REST client for a Nightscout site.
///
/// Auth: when `token` is set it is appended as a `token` query parameter
/// (takes precedence); otherwise `apiSecret` is sent as the
/// `API-SECRET: <lowercase hex SHA1(secret)>` header.
public struct NightscoutClient: Sendable {
    public let baseURL: URL
    private let token: String?
    private let apiSecret: String?
    private let session: URLSession

    /// - Parameters:
    ///   - baseURLString: site URL; trailing slashes are stripped. Must be http/https.
    ///   - token: optional Nightscout "subject" access token (query param auth).
    ///   - apiSecret: optional API secret (SHA1 header auth).
    public init(baseURLString: String, token: String? = nil, apiSecret: String? = nil,
                session: URLSession = .shared) throws {
        var cleaned = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        while cleaned.hasSuffix("/") { cleaned.removeLast() }
        guard !cleaned.isEmpty,
              let url = URL(string: cleaned),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil else {
            throw NightscoutError.invalidURL
        }
        self.baseURL = url
        let nonEmpty: (String?) -> String? = { s in
            guard let s = s?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
            return s
        }
        self.token = nonEmpty(token)
        self.apiSecret = nonEmpty(apiSecret)
        self.session = session
    }

    /// Convenience: SHA1 hex digest of a plain-text API secret.
    public static func sha1Hex(_ string: String) -> String {
        Insecure.SHA1.hash(data: Data(string.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    /// Latest glucose entries, newest first. With `since`, only entries at or
    /// after that instant are returned (up to `count`) — pass a generous count
    /// so high-frequency uploaders (1-min AID rigs) still cover the window.
    public func fetchEntries(count: Int = 60, since: Date? = nil) async throws -> [GlucoseEntry] {
        var items = [URLQueryItem(name: "count", value: String(count))]
        if let since {
            let ms = Int(since.timeIntervalSince1970 * 1000)
            items.append(URLQueryItem(name: "find[date][$gte]", value: String(ms)))
        }
        return try await get(path: "/api/v1/entries.json", queryItems: items)
    }

    /// Treatments created at or after `since` (max `count`).
    public func fetchTreatments(since: Date, count: Int = 100) async throws -> [Treatment] {
        let iso = Self.isoString(since)
        return try await get(path: "/api/v1/treatments.json", queryItems: [
            URLQueryItem(name: "count", value: String(count)),
            URLQueryItem(name: "find[created_at][$gte]", value: iso),
        ])
    }

    /// Most recent uploader device status (battery). Failures should be treated as non-fatal by callers.
    public func fetchDeviceStatus() async throws -> DeviceStatus? {
        let list: [DeviceStatus] = try await get(path: "/api/v1/devicestatus.json", query: ["count": "1"])
        return list.first
    }

    /// Server status for the "Test Connection" button.
    public func fetchServerStatus() async throws -> NightscoutServerStatus {
        try await get(path: "/api/v1/status.json", query: [:])
    }

    private static func isoString(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }

    private func get<T: Decodable>(path: String, query: [String: String]) async throws -> T {
        try await get(path: path, queryItems: query.map { URLQueryItem(name: $0.key, value: $0.value) })
    }

    private func get<T: Decodable>(path: String, queryItems: [URLQueryItem]) async throws -> T {
        var components = URLComponents(string: baseURL.absoluteString + path)
        var items = queryItems
        if let token { items.append(URLQueryItem(name: "token", value: token)) }
        components?.queryItems = items.isEmpty ? nil : items
        guard let url = components?.url else { throw NightscoutError.invalidURL }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        if token == nil, let apiSecret {
            request.setValue(Self.sha1Hex(apiSecret), forHTTPHeaderField: "API-SECRET")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as NightscoutError {
            throw error
        } catch {
            throw NightscoutError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw NightscoutError.network("No HTTP response.")
        }
        switch http.statusCode {
        case 200...299: break
        case 401, 403: throw NightscoutError.unauthorized
        default: throw NightscoutError.httpError(http.statusCode)
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw NightscoutError.decoding(error.localizedDescription)
        }
    }
}
