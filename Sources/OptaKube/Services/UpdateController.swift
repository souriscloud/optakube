import AppKit
import Sparkle

/// Single owner of Sparkle. Both the macOS app menu's "Check for Updates…" item and
/// the menu-bar-icon dropdown call into this singleton so the same updater handles
/// the user-triggered check and the scheduled background check.
///
/// Sparkle reads `SUFeedURL` (the single stable appcast) + `SUPublicEDKey` from
/// Info.plist, which is only present in a real .app bundle. Under `swift run`
/// there's no bundle, so we skip init gracefully and the menu items become no-ops
/// (still visible — disabled).
@MainActor
final class UpdateController: NSObject {
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
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        // Scheduled checks only fire once per SUScheduledCheckInterval (~24h). A
        // user who quits + relaunches within the day would never get a new build
        // until the next scheduled tick. Kick off a silent background check on
        // launch so updates land on next open. The standard driver only surfaces
        // UI when an update is actually found, so this is invisible when current.
        //
        // Gated on the user's own preference. Sparkle's documentation is explicit that
        // `checkForUpdatesInBackground` should only be called when
        // `automaticallyChecksForUpdates` is enabled, both because calling it later can
        // interfere with the scheduler and because someone who declined automatic checks
        // should not have the app reach out to GitHub on every launch regardless — this is
        // a tool that runs inside enterprise networks.
        DispatchQueue.main.async { [weak self] in
            guard let updater = self?.standardController?.updater,
                  updater.automaticallyChecksForUpdates else { return }
            updater.checkForUpdatesInBackground()
        }
    }

    func checkForUpdates(_ sender: Any?) {
        standardController?.checkForUpdates(sender)
    }
}
