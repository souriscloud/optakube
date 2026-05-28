import AppKit
import Sparkle

/// Single owner of Sparkle. Both the macOS app menu's "Check for Updates…" item and
/// the menu-bar-icon dropdown call into this singleton so the same updater handles
/// the user-triggered check and the scheduled background check.
///
/// Sparkle reads `SUFeedURL` + `SUPublicEDKey` from Info.plist, which is only present
/// in a real .app bundle. Under `swift run` there's no bundle, so we skip init
/// gracefully and the menu items become no-ops (still visible — disabled).
/// Update channel — release (default, stable) or beta (pre-releases via appcast-beta.xml).
enum UpdateChannel: String, CaseIterable, Identifiable {
    case release, beta
    var id: String { rawValue }
    var displayName: String { self == .beta ? "Beta" : "Release" }
}

@MainActor
final class UpdateController: NSObject, SPUUpdaterDelegate {
    static let shared = UpdateController()

    private(set) var standardController: SPUStandardUpdaterController?

    /// True only when Sparkle was initialised (i.e. we're running from a real .app
    /// bundle). UI uses this to disable the menu items under `swift run`.
    var isAvailable: Bool { standardController != nil }

    override init() {
        super.init()
        guard Bundle.main.bundleIdentifier != nil else { return }
        self.standardController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        // Scheduled checks only fire once per SUScheduledCheckInterval (~24h). A
        // user who quits + relaunches within the day would never get a new build
        // until the next scheduled tick. Kick off a silent background check on
        // launch so updates land on next open. The standard driver only surfaces
        // UI when an update is actually found, so this is invisible when current.
        DispatchQueue.main.async { [weak self] in
            self?.standardController?.updater.checkForUpdatesInBackground()
        }
    }

    func checkForUpdates(_ sender: Any?) {
        standardController?.checkForUpdates(sender)
    }

    // MARK: - SPUUpdaterDelegate

    /// Route between stable and beta appcasts based on the user's chosen channel.
    nonisolated func feedURLString(for updater: SPUUpdater) -> String? {
        let channel = MainActor.assumeIsolated { Self.currentChannel }
        switch channel {
        case .beta: return "https://raw.githubusercontent.com/souriscloud/optakube/master/appcast-beta.xml"
        case .release: return "https://raw.githubusercontent.com/souriscloud/optakube/master/appcast.xml"
        }
    }

    static var currentChannel: UpdateChannel {
        get {
            let raw = UserDefaults.standard.string(forKey: "updateChannel") ?? UpdateChannel.release.rawValue
            return UpdateChannel(rawValue: raw) ?? .release
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "updateChannel") }
    }
}
