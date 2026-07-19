import Foundation
@testable import MacscoutCore

/// URLProtocol stub that captures requests and returns scripted responses.
final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    static var requestHandler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?
    nonisolated(unsafe) static var lastRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        MockURLProtocol.lastRequest = request
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

enum NightscoutClientTests {
    static func makeClient(base: String = "https://ns.example.com/", token: String? = nil, secret: String? = nil) throws -> NightscoutClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return try NightscoutClient(baseURLString: base, token: token, apiSecret: secret,
                                    session: URLSession(configuration: config))
    }

    static func respond(status: Int = 200, json: String) {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: status,
                                           httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            return (response, Data(json.utf8))
        }
    }

    // Fixture shaped like real `/api/v1/entries.json` output.
    static let entriesJSON = """
    [
      {"_id":"65534a1f","device":"xDrip-DexcomG6","date":1699999999000,"dateString":"2023-11-14T22:13:19.000Z","sgv":123,"delta":-2.001,"direction":"FortyFiveDown","type":"sgv","utcOffset":0},
      {"_id":"65534900","device":"xDrip-DexcomG6","date":1699999699000,"dateString":"2023-11-14T22:08:19.000Z","sgv":125,"direction":"Flat","type":"sgv","utcOffset":0}
    ]
    """

    static func fetchEntriesDecodes() async throws {
        respond(json: entriesJSON)
        let entries = try await makeClient().fetchEntries(count: 2)
        checkEqual(entries.count, 2)
        checkEqual(entries[0].id, "65534a1f")
        checkEqual(entries[0].sgv, 123)
        checkClose(entries[0].delta ?? 0, -2.001)
        checkEqual(entries[0].direction, .fortyFiveDown)
        checkEqual(entries[0].device, "xDrip-DexcomG6")
        checkClose(entries[0].date.timeIntervalSince1970, 1699999999, tolerance: 0.5)
        check(entries[1].delta == nil)
        checkEqual(entries[1].direction, .flat)
    }

    static func apiSecretSentAsSHA1Header() async throws {
        respond(json: "[]")
        _ = try await makeClient(secret: "mysecret").fetchEntries(count: 1)
        let request = unwrap(MockURLProtocol.lastRequest)
        checkEqual(request.value(forHTTPHeaderField: "API-SECRET"), NightscoutClient.sha1Hex("mysecret"))
        // SHA1("mysecret") is a known digest.
        checkEqual(request.value(forHTTPHeaderField: "API-SECRET"), "e9fe51f94eadabf54dbf2fbbd57188b9abee436e")
        check(!(request.url?.query?.contains("token=") ?? false))
    }

    static func tokenTakesPrecedenceOverSecret() async throws {
        respond(json: "[]")
        _ = try await makeClient(token: "abc123", secret: "mysecret").fetchEntries(count: 1)
        let request = unwrap(MockURLProtocol.lastRequest)
        check(request.value(forHTTPHeaderField: "API-SECRET") == nil)
        let components = unwrap(URLComponents(url: request.url!, resolvingAgainstBaseURL: false))
        check(components.queryItems?.contains(URLQueryItem(name: "token", value: "abc123")) ?? false)
        check(components.queryItems?.contains(URLQueryItem(name: "count", value: "1")) ?? false)
    }

    static func entriesSinceQuery() async throws {
        respond(json: entriesJSON)
        let since = Date(timeIntervalSince1970: 1699999000)
        _ = try await makeClient().fetchEntries(count: 3000, since: since)
        let request = unwrap(MockURLProtocol.lastRequest)
        checkEqual(request.url?.path, "/api/v1/entries.json")
        let query = request.url?.query ?? ""
        // Epoch-milliseconds lower bound; accept encoded and unencoded brackets.
        check(query.contains("find[date][$gte]=1699999000000") || query.contains("find%5Bdate%5D%5B$gte%5D=1699999000000"),
              "missing find[date][$gte] in query: \(query)")
        check(query.contains("count=3000"))
    }

    static func treatmentsQueryAndDecode() async throws {
        let treatmentsJSON = """
        [
          {"_id":"t1","created_at":"2023-11-14T22:00:00.000Z","eventType":"Carb Correction","carbs":20,"insulin":null,"notes":"snack"},
          {"_id":"t2","created_at":"2023-11-14T21:00:00.000Z","eventType":"Correction Bolus","insulin":1.5}
        ]
        """
        respond(json: treatmentsJSON)
        let since = Date(timeIntervalSince1970: 1699999000)
        let treatments = try await makeClient(token: "tok").fetchTreatments(since: since)
        checkEqual(treatments.count, 2)
        checkEqual(treatments[0].carbs, 20)
        check(treatments[0].insulin == nil)
        checkEqual(treatments[1].insulin, 1.5)
        checkClose(treatments[0].createdAt.timeIntervalSince1970, 1699999200, tolerance: 1)

        let request = unwrap(MockURLProtocol.lastRequest)
        checkEqual(request.url?.path, "/api/v1/treatments.json")
        let query = request.url?.query ?? ""
        // Accept both encoded and unencoded bracket forms.
        check(query.contains("find[created_at][$gte]=") || query.contains("find%5Bcreated_at%5D%5B$gte%5D="),
              "missing find[created_at][$gte] in query: \(query)")
        check(query.contains("count=100"))
    }

    static func deviceStatusDecodes() async throws {
        respond(json: """
        [{"created_at":"2023-11-14T22:13:00.000Z","uploader":{"battery":82}}]
        """)
        let status = try await makeClient().fetchDeviceStatus()
        checkEqual(status?.uploaderBattery, 82)
    }

    static func serverStatusDecodes() async throws {
        respond(json: """
        {"status":"ok","name":"nightscout","version":"15.0.2","apiEnabled":true}
        """)
        let status = try await makeClient().fetchServerStatus()
        checkEqual(status.status, "ok")
        checkEqual(status.version, "15.0.2")
        checkEqual(status.apiEnabled, true)
    }

    static func unauthorized() async {
        respond(status: 401, json: "{}")
        do {
            _ = try await makeClient().fetchEntries()
            check(false, "expected unauthorized error")
        } catch NightscoutError.unauthorized {
            // expected
        } catch {
            check(false, "wrong error: \(error)")
        }
    }

    static func httpError() async {
        respond(status: 500, json: "{}")
        do {
            _ = try await makeClient().fetchEntries()
            check(false, "expected httpError")
        } catch NightscoutError.httpError(let code) {
            checkEqual(code, 500)
        } catch {
            check(false, "wrong error: \(error)")
        }
    }

    static func decodingError() async {
        respond(json: "{\"not\":\"an array\"}")
        do {
            _ = try await makeClient().fetchEntries()
            check(false, "expected decoding error")
        } catch NightscoutError.decoding {
            // expected
        } catch {
            check(false, "wrong error: \(error)")
        }
    }

    static func invalidURLs() {
        for bad in ["", "ftp://example.com", "not a url"] {
            do {
                _ = try NightscoutClient(baseURLString: bad)
                check(false, "expected invalidURL for \(bad)")
            } catch NightscoutError.invalidURL {
                // expected
            } catch {
                check(false, "wrong error for \(bad): \(error)")
            }
        }
    }

    static func baseURLTrailingSlashStripped() async throws {
        respond(json: "[]")
        let client = try makeClient(base: "https://ns.example.com/")
        checkEqual(client.baseURL.absoluteString, "https://ns.example.com")
        _ = try await client.fetchEntries()
        checkEqual(MockURLProtocol.lastRequest?.url?.path, "/api/v1/entries.json")
    }

    static func trendArrowMapping() {
        checkEqual(TrendArrow.doubleUp.arrow, "↑↑")
        checkEqual(TrendArrow.singleUp.arrow, "↑")
        checkEqual(TrendArrow.fortyFiveUp.arrow, "↗")
        checkEqual(TrendArrow.flat.arrow, "→")
        checkEqual(TrendArrow.fortyFiveDown.arrow, "↘")
        checkEqual(TrendArrow.singleDown.arrow, "↓")
        checkEqual(TrendArrow.doubleDown.arrow, "↓↓")
        checkEqual(TrendArrow.notComputable.arrow, "–")
        checkEqual(TrendArrow.none.arrow, "–")
        for raw in ["DoubleUp", "SingleUp", "FortyFiveUp", "Flat", "FortyFiveDown",
                    "SingleDown", "DoubleDown", "NOT COMPUTABLE", "NONE", "RateOutOfRange"] {
            check(TrendArrow(rawValue: raw) != nil, "missing TrendArrow for \(raw)")
        }
    }

    static var tests: [(String, TestBody)] {
        [("fetchEntriesDecodes", sync(fetchEntriesDecodes)),
         ("entriesSinceQuery", sync(entriesSinceQuery)),
         ("apiSecretSentAsSHA1Header", sync(apiSecretSentAsSHA1Header)),
         ("tokenTakesPrecedenceOverSecret", sync(tokenTakesPrecedenceOverSecret)),
         ("treatmentsQueryAndDecode", sync(treatmentsQueryAndDecode)),
         ("deviceStatusDecodes", sync(deviceStatusDecodes)),
         ("serverStatusDecodes", sync(serverStatusDecodes)),
         ("unauthorized", sync(unauthorized)),
         ("httpError", sync(httpError)),
         ("decodingError", sync(decodingError)),
         ("invalidURLs", invalidURLs),
         ("baseURLTrailingSlashStripped", sync(baseURLTrailingSlashStripped)),
         ("trendArrowMapping", trendArrowMapping)]
    }
}

/// Registers the suites that run in-process in the test helper.
func registerLocalTests() {
    register("UnitConverter", UnitConverterTests.tests)
    register("AlertEngine", AlertEngineTests.tests)
    register("StatsCalculator", StatsCalculatorTests.tests)
    register("Chiptune", ChiptuneTests.tests)
}

/// Registers the URLSession-based suites; run in a child process (see
/// HarnessBootstrap.swift for why).
func registerClientTests() {
    register("NightscoutClient", NightscoutClientTests.tests)
}
