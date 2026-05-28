import SwiftUI
import Foundation
import AppKit

/// Unified menu-bar-icon dropdown. Mirrors the structure of the app menu so the
/// two surfaces feel consistent: open windows on top, app-wide actions on the
/// bottom, port-forwards in between because they're cross-window/global state.
///
/// Rendered as a native NSMenu via `.menuBarExtraStyle(.menu)`, so use plain
/// Buttons + Dividers only — no custom SwiftUI layouts in here.
struct MenuBarDropdownView: View {
    var pfManager = PortForwardManager.shared
    var windowManager = WindowManager.shared
    var updater = UpdateController.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        // Top: welcome / hub
        Button("Welcome…") { windowManager.showWelcomeWindow() }
        Button("Bring OptaKube to Front") { NSApp.activate(ignoringOtherApps: true) }

        Divider()

        // Open cluster windows
        Section("Open Clusters") {
            let entries = Array(windowManager.activeWindows.values)
            if entries.isEmpty {
                Button("— none —") { }.disabled(true)
            } else {
                ForEach(entries, id: \.id) { vm in
                    let conn = vm.activeConnections.first
                    let connId = conn?.id ?? ""
                    let custom = ClusterCustomizationStore.shared.get(for: connId)
                    let displayName = custom.displayName ?? conn?.name ?? "Cluster"
                    Button(displayName) {
                        windowManager.bringWindowToFront(vm.id)
                    }
                }
            }
        }

        // Port forwards (only show the section when there's something to show)
        if !pfManager.activeForwards.isEmpty {
            Divider()
            Section("Port Forwards") {
                ForEach(pfManager.activeForwards) { pf in
                    Button("\(pf.podName) — localhost:\(pf.localPort) → \(pf.remotePort)") {
                        pfManager.remove(pf)
                    }
                }
                if pfManager.activeForwards.count > 1 {
                    Button("Stop All Forwards") { pfManager.stopAll() }
                }
            }
        }

        Divider()

        // App-wide actions — same set as the macOS app menu, so the surfaces match
        Button("About OptaKube") { openWindow(id: "about") }
        Button("Check for Updates…") { updater.checkForUpdates(nil) }
            .disabled(!updater.isAvailable)
        Button("Settings…") {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
        .keyboardShortcut(",", modifiers: .command)

        Divider()

        Button("Quit OptaKube") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q", modifiers: .command)
    }
}
