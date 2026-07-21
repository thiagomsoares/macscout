import Foundation
@testable import MacscoutCore

enum AppVersionTests {
    static func parsesPlainAndVPrefix() {
        checkEqual(AppVersion(string: "1.2.3"), AppVersion(major: 1, minor: 2, patch: 3))
        checkEqual(AppVersion(string: "v0.1.0"), AppVersion(major: 0, minor: 1, patch: 0))
        checkEqual(AppVersion(string: "V2.0.1"), AppVersion(major: 2, minor: 0, patch: 1))
        checkEqual(AppVersion(string: "1.4"), AppVersion(major: 1, minor: 4, patch: 0))
    }

    static func stripsPrereleaseAndBuild() {
        checkEqual(AppVersion(string: "1.2.3-beta.1"), AppVersion(major: 1, minor: 2, patch: 3))
        checkEqual(AppVersion(string: "1.2.3+42"), AppVersion(major: 1, minor: 2, patch: 3))
    }

    static func rejectsGarbage() {
        check(AppVersion(string: "") == nil)
        check(AppVersion(string: "nope") == nil)
        check(AppVersion(string: "1") == nil)
        check(AppVersion(string: "a.b.c") == nil)
    }

    static func comparisonOrder() {
        let a = AppVersion(major: 0, minor: 1, patch: 0)
        let b = AppVersion(major: 0, minor: 1, patch: 1)
        let c = AppVersion(major: 0, minor: 2, patch: 0)
        let d = AppVersion(major: 1, minor: 0, patch: 0)
        check(a < b)
        check(b < c)
        check(c < d)
        check(!(a < a))
        check(a == AppVersion(string: "v0.1.0"))
    }

    static func descriptionIsDotted() {
        checkEqual(AppVersion(major: 1, minor: 0, patch: 9).description, "1.0.9")
    }

    static var tests: [(String, TestBody)] {
        [("parsesPlainAndVPrefix", parsesPlainAndVPrefix),
         ("stripsPrereleaseAndBuild", stripsPrereleaseAndBuild),
         ("rejectsGarbage", rejectsGarbage),
         ("comparisonOrder", comparisonOrder),
         ("descriptionIsDotted", descriptionIsDotted)]
    }
}

enum GitHubReleaseTests {
    static let sampleJSON = """
    {
      "tag_name": "v0.2.0",
      "name": "Macscout 0.2.0",
      "html_url": "https://github.com/thiagomsoares/macscout/releases/tag/v0.2.0",
      "body": "Notes",
      "prerelease": false,
      "draft": false,
      "published_at": "2026-07-21T12:00:00Z",
      "assets": [
        {
          "name": "Macscout-0.2.0.dmg",
          "browser_download_url": "https://github.com/thiagomsoares/macscout/releases/download/v0.2.0/Macscout-0.2.0.dmg",
          "size": 1234567,
          "content_type": "application/x-apple-diskimage"
        },
        {
          "name": "checksums.txt",
          "browser_download_url": "https://example.com/checksums.txt",
          "size": 40,
          "content_type": "text/plain"
        }
      ]
    }
    """.data(using: .utf8)!

    static func decodesLatestPayload() {
        let release = try! GitHubReleaseClient.decodeRelease(from: sampleJSON)
        checkEqual(release.tagName, "v0.2.0")
        checkEqual(release.version, AppVersion(string: "0.2.0"))
        checkEqual(release.prerelease, false)
        checkEqual(release.dmgAsset?.name, "Macscout-0.2.0.dmg")
        checkEqual(release.dmgAsset?.size, 1234567)
        checkEqual(release.dmgURL?.absoluteString,
                   "https://github.com/thiagomsoares/macscout/releases/download/v0.2.0/Macscout-0.2.0.dmg")
    }

    static func prefersDmgAsset() {
        let release = try! GitHubReleaseClient.decodeRelease(from: sampleJSON)
        checkEqual(release.assets.count, 2)
        check(release.dmgAsset?.name.hasSuffix(".dmg") == true)
    }

    static func rejectsGarbageJSON() {
        var threw = false
        do {
            _ = try GitHubReleaseClient.decodeRelease(from: Data("{\"nope\":true}".utf8))
        } catch {
            threw = true
            checkEqual(error as? GitHubReleaseClient.ClientError, .decoding)
        }
        check(threw, "expected decoding error")
    }

    static func newerThanInstalled() {
        let release = try! GitHubReleaseClient.decodeRelease(from: sampleJSON)
        let installed = AppVersion(string: "0.1.0")!
        let remote = release.version!
        check(remote > installed)
        check(!(AppVersion(string: "0.2.0")! > remote))
    }

    static var tests: [(String, TestBody)] {
        [("decodesLatestPayload", decodesLatestPayload),
         ("prefersDmgAsset", prefersDmgAsset),
         ("rejectsGarbageJSON", rejectsGarbageJSON),
         ("newerThanInstalled", newerThanInstalled)]
    }
}
