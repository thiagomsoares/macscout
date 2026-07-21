import AppKit
import Combine
import Foundation
import MacscoutCore

/// Checks GitHub Releases for a newer Macscout and can download the DMG
/// straight into ~/Downloads, then opens it so the user can drag into
/// Applications. Zero dependencies — plain URLSession.
@MainActor
final class UpdateController: ObservableObject {
    enum Status: Equatable {
        case idle
        case checking
        case upToDate(current: String)
        /// A newer release is available.
        case available(version: String, releaseURL: URL, dmgURL: URL, dmgName: String, bytes: Int)
        case downloading(fraction: Double?)
        case downloaded(fileURL: URL)
        case failed(String)
    }

    @Published private(set) var status: Status = .idle

    /// Bundle short version, e.g. `"0.1.0"`. Overridable in tests.
    let currentVersionString: String
    private let latestURL: URL
    private let session: URLSession
    private let downloadsDirectory: URL
    private var downloadTask: URLSessionDownloadTask?
    private var progressObservation: NSKeyValueObservation?

    init(currentVersionString: String? = nil,
         latestURL: URL = GitHubReleaseClient.defaultLatestURL,
         session: URLSession = .shared,
         downloadsDirectory: URL? = nil) {
        self.currentVersionString = currentVersionString
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
            ?? "0.0.0"
        self.latestURL = latestURL
        self.session = session
        self.downloadsDirectory = downloadsDirectory
            ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
    }

    var currentVersion: AppVersion? { AppVersion(string: currentVersionString) }

    /// Quiet background check used on launch. Only transitions out of `.idle`
    /// / `.upToDate` when something newer is actually available (or on hard
    /// failure we stay quiet — launch must never nag about network blips).
    func checkInBackground() {
        Task { await check(quiet: true) }
    }

    /// Interactive check (About tab / menu item).
    func check(quiet: Bool = false) async {
        // Don't clobber an in-flight download.
        if case .downloading = status { return }
        if !quiet { status = .checking }

        do {
            let release = try await GitHubReleaseClient.fetchLatest(
                url: latestURL,
                session: session,
                userAgent: "Macscout/\(currentVersionString)"
            )
            guard let remote = release.version else {
                if !quiet { status = .failed(L("Could not read the latest version.")) }
                return
            }
            guard let local = currentVersion else {
                if !quiet { status = .failed(L("Could not read the installed version.")) }
                return
            }
            if remote <= local {
                status = .upToDate(current: local.description)
                return
            }
            guard let asset = release.dmgAsset,
                  let dmgURL = URL(string: asset.browserDownloadURL),
                  let pageURL = URL(string: release.htmlURL) else {
                if !quiet { status = .failed(L("Latest release has no DMG to download.")) }
                return
            }
            status = .available(version: remote.description,
                                releaseURL: pageURL,
                                dmgURL: dmgURL,
                                dmgName: asset.name,
                                bytes: asset.size)
        } catch {
            if quiet { return }
            status = .failed(error.localizedDescription)
        }
    }

    /// Downloads the DMG into ~/Downloads and opens it (Finder / disk image).
    func download() async {
        guard case let .available(_, _, dmgURL, dmgName, _) = status else { return }
        status = .downloading(fraction: nil)

        do {
            let (tempURL, response) = try await session.download(from: dmgURL)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                status = .failed(LF("Download failed (HTTP %d).", http.statusCode))
                return
            }
            let dest = uniqueDestination(named: dmgName)
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.moveItem(at: tempURL, to: dest)
            status = .downloaded(fileURL: dest)
            NSWorkspace.shared.activateFileViewerSelecting([dest])
            NSWorkspace.shared.open(dest)
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    /// Opens the release page in the browser (notes / manual download).
    func openReleasePage() {
        guard case let .available(_, releaseURL, _, _, _) = status else { return }
        NSWorkspace.shared.open(releaseURL)
    }

    /// Opens a previously downloaded DMG again.
    func openDownloaded() {
        guard case let .downloaded(fileURL) = status else { return }
        NSWorkspace.shared.open(fileURL)
    }

    /// Menu-bar / keyboard entry point: check, then present a native alert.
    func checkAndPresentAlert() {
        Task {
            await check(quiet: false)
            presentAlertForCurrentStatus()
        }
    }

    private func presentAlertForCurrentStatus() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        switch status {
        case .upToDate(let current):
            alert.messageText = L("You're up to date")
            alert.informativeText = LF("Macscout %@ is the latest release.", current)
            alert.addButton(withTitle: L("OK"))
            alert.runModal()
        case .available(let version, _, _, let dmgName, let bytes):
            alert.messageText = LF("Macscout %@ is available", version)
            alert.informativeText = LF(
                "You have %@. Download %@ (%@) to your Downloads folder and open it to install.",
                currentVersionString, dmgName, Self.formatBytes(bytes))
            alert.addButton(withTitle: L("Download"))
            alert.addButton(withTitle: L("View Release"))
            alert.addButton(withTitle: L("Later"))
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                Task { await download() }
            case .alertSecondButtonReturn:
                openReleasePage()
            default:
                break
            }
        case .failed(let message):
            alert.alertStyle = .warning
            alert.messageText = L("Could not check for updates")
            alert.informativeText = message
            alert.addButton(withTitle: L("OK"))
            alert.runModal()
        case .checking, .downloading, .downloaded, .idle:
            break
        }
    }

    private func uniqueDestination(named name: String) -> URL {
        let base = downloadsDirectory.appendingPathComponent(name)
        if !FileManager.default.fileExists(atPath: base.path) { return base }
        let stem = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var i = 2
        while true {
            let candidate = downloadsDirectory
                .appendingPathComponent("\(stem)-\(i)")
                .appendingPathExtension(ext)
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            i += 1
        }
    }

    static func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useMB, .useKB, .useBytes]
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
