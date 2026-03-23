import SwiftUI
import AppKit

@Observable
final class WindowManager {
    static let shared = WindowManager()

    private(set) var activeWindows: [String: AppViewModel] = [:]
    // Track NSWindow references for reliable window activation
    private(set) var windowRefs: [String: NSWindow] = [:]

    var hasActiveWindows: Bool { !activeWindows.isEmpty }

    private init() {}

    func createClusterWindow(clusterIds: Set<String>) -> String {
        let vm = AppViewModel()
        vm.selectedClusterIds = clusterIds
        vm.showMainWindow = true
        vm.restoreState()
        activeWindows[vm.id] = vm
        return vm.id
    }

    func viewModel(for windowId: String) -> AppViewModel? {
        activeWindows[windowId]
    }

    func registerWindow(_ window: NSWindow, for windowId: String) {
        windowRefs[windowId] = window
    }

    func bringWindowToFront(_ windowId: String) {
        if let window = windowRefs[windowId] {
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    func windowClosed(_ windowId: String) {
        if let vm = activeWindows[windowId] {
            vm.stopAutoRefresh()
            vm.stopWatch()
        }
        activeWindows.removeValue(forKey: windowId)
        windowRefs.removeValue(forKey: windowId)

        if activeWindows.isEmpty {
            showWelcomeWindow()
        }
    }

    func showWelcomeWindow() {
        DispatchQueue.main.async {
            for window in NSApplication.shared.windows {
                if window.title == "OptaKube" || window.identifier?.rawValue.contains("welcome") == true {
                    window.makeKeyAndOrderFront(nil)
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    return
                }
            }
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }
}
