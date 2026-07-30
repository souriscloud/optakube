import SwiftUI
import AppKit

@main
struct OptaKubeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.openWindow) private var openWindow
    // Sparkle ownership lives in UpdateController.shared — same singleton powers
    // both the app menu's "Check for Updates…" and the menu-bar-icon entry.
    private let updater = UpdateController.shared

    var body: some Scene {
        // Welcome / hub window
        Window("OptaKube", id: "welcome") {
            WelcomeWindow()
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 680, height: 560)

        // Cluster windows
        WindowGroup(id: "cluster", for: String.self) { $windowId in
            ClusterWindowView(windowId: windowId)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1200, height: 800)
        .commands {
            // Suppress SwiftUI's synthesized File ▸ New Window for this WindowGroup. It
            // took ⌘N (colliding with the toolbar's create-resource button) and opened a
            // cluster window with a nil windowId, which has no view model and so sat on
            // "Connecting…" forever with no error and no way out but closing it. New
            // windows come from the Welcome hub, which is the documented entry point.
            CommandGroup(replacing: .newItem) {}

            // About
            CommandGroup(replacing: .appInfo) {
                Button("About OptaKube") {
                    openWindow(id: "about")
                }
                Divider()
                Button("Check for Updates…") {
                    updater.checkForUpdates(nil)
                }
                .disabled(!updater.isAvailable)
            }

            // Resource type shortcuts
            CommandMenu("Resources") {
                Button("Pods") { switchResourceType(.pods) }
                    .keyboardShortcut("1", modifiers: .command)
                Button("Deployments") { switchResourceType(.deployments) }
                    .keyboardShortcut("2", modifiers: .command)
                Button("Services") { switchResourceType(.services) }
                    .keyboardShortcut("3", modifiers: .command)
                Button("StatefulSets") { switchResourceType(.statefulSets) }
                    .keyboardShortcut("4", modifiers: .command)
                Button("Nodes") { switchResourceType(.nodes) }
                    .keyboardShortcut("5", modifiers: .command)
                Button("Jobs") { switchResourceType(.jobs) }
                    .keyboardShortcut("6", modifiers: .command)
                Button("ConfigMaps") { switchResourceType(.configMaps) }
                    .keyboardShortcut("7", modifiers: .command)
                Button("Secrets") { switchResourceType(.secrets) }
                    .keyboardShortcut("8", modifiers: .command)
                Button("Ingresses") { switchResourceType(.ingresses) }
                    .keyboardShortcut("9", modifiers: .command)
            }

            // Help → Send Feedback (pre-filled GitHub issue) + issues list.
            CommandGroup(replacing: .help) {
                Button("Send Feedback…") {
                    openWindow(id: "feedback")
                }
                Button("OptaKube Issues on GitHub") {
                    if let url = GitHubFeedback.issuesListURL { NSWorkspace.shared.open(url) }
                }
            }
        }

        // Menu bar icon — uses cube symbol (matches app icon), supports macOS tinting.
        // `.menu` style renders the contents as a native NSMenu so it looks like every
        // other macOS menu bar app instead of a custom SwiftUI popover.
        MenuBarExtra("OptaKube", systemImage: "square.stack.3d.up") {
            MenuBarDropdownView()
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
        }

        // About window
        Window("About OptaKube", id: "about") {
            AboutView()
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)

        // Feedback window — pre-fills a GitHub issue, no backend.
        Window("Send Feedback", id: "feedback") {
            FeedbackView()
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)
    }

    private func switchResourceType(_ type: ResourceType) {
        guard let vm = WindowManager.shared.focusedViewModel else { return }
        vm.selectBuiltInType(type)
        Task { await vm.refresh() }
    }
}

/// Wraps MainWindow with its per-window AppViewModel
struct ClusterWindowView: View {
    let windowId: String?
    @State private var vm: AppViewModel?

    var body: some View {
        Group {
            if let vm = vm {
                MainWindow()
                    .environment(vm)
            } else {
                // Belt and braces for a window opened without a usable id (a restored
                // session, or any path that bypasses the Welcome hub). This used to be an
                // indefinite "Connecting…" spinner with no explanation and no escape.
                VStack(spacing: 12) {
                    Image(systemName: "square.stack.3d.up.slash")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("No cluster in this window")
                        .font(.title3)
                        .fontWeight(.medium)
                    Text("Pick a cluster from the welcome window to open a session.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Open Welcome Window") {
                        WindowManager.shared.showWelcomeWindow()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(WindowAccessor(windowId: windowId))
        .onAppear {
            guard let windowId = windowId else { return }
            if let existing = WindowManager.shared.viewModel(for: windowId) {
                vm = existing
            }
        }
        .onDisappear {
            guard let windowId = windowId, let vm = vm else { return }
            vm.saveState()
            vm.stopAutoRefresh()
            WindowManager.shared.windowClosed(windowId)
        }
    }
}

/// Helper to capture the NSWindow reference
struct WindowAccessor: NSViewRepresentable {
    let windowId: String?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let windowId = windowId, let window = view.window {
                WindowManager.shared.registerWindow(window, for: windowId)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let windowId = windowId, let window = nsView.window {
                WindowManager.shared.registerWindow(window, for: windowId)
            }
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        setAppIcon()
    }

    private func setAppIcon() {
        // Try bundled .icns first
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApplication.shared.applicationIconImage = icon
            return
        }

        // Fallback: generate icon with proper Apple HIG margins (~10% inset)
        let size: CGFloat = 512
        let icon = NSImage(size: NSSize(width: size, height: size))
        icon.lockFocus()
        guard let ctx = NSGraphicsContext.current?.cgContext else { icon.unlockFocus(); return }

        let margin = size * 0.1
        let iconSize = size - margin * 2
        let iconRect = CGRect(x: margin, y: margin, width: iconSize, height: iconSize)
        let r = iconSize * 0.22
        ctx.addPath(CGPath(roundedRect: iconRect, cornerWidth: r, cornerHeight: r, transform: nil))
        ctx.clip()

        let colors = [CGColor(red: 0.25, green: 0.55, blue: 1.0, alpha: 1.0),
                      CGColor(red: 0.12, green: 0.32, blue: 0.85, alpha: 1.0)] as CFArray
        let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
        ctx.drawLinearGradient(grad, start: CGPoint(x: margin, y: margin + iconSize), end: CGPoint(x: margin + iconSize, y: margin), options: [])

        let cx = size / 2, cy = size / 2, sz = iconSize * 0.28
        ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
        ctx.setLineWidth(iconSize * 0.02)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        let top = CGPoint(x: cx, y: cy - sz * 0.65)
        let mid = CGPoint(x: cx, y: cy + sz * 0.05)
        let bot = CGPoint(x: cx, y: cy + sz * 0.75)
        let left = CGPoint(x: cx - sz * 0.7, y: cy - sz * 0.25)
        let right = CGPoint(x: cx + sz * 0.7, y: cy - sz * 0.25)
        let botLeft = CGPoint(x: cx - sz * 0.7, y: cy + sz * 0.45)
        let botRight = CGPoint(x: cx + sz * 0.7, y: cy + sz * 0.45)

        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.15))
        ctx.move(to: top); ctx.addLine(to: right); ctx.addLine(to: mid); ctx.addLine(to: left); ctx.closePath(); ctx.fillPath()
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.08))
        ctx.move(to: left); ctx.addLine(to: mid); ctx.addLine(to: bot); ctx.addLine(to: botLeft); ctx.closePath(); ctx.fillPath()
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.04))
        ctx.move(to: right); ctx.addLine(to: mid); ctx.addLine(to: bot); ctx.addLine(to: botRight); ctx.closePath(); ctx.fillPath()

        for (a, b) in [(top,right),(top,left),(left,botLeft),(right,botRight),(mid,left),(mid,right),(mid,bot),(botLeft,bot),(botRight,bot)] {
            ctx.move(to: a); ctx.addLine(to: b); ctx.strokePath()
        }

        icon.unlockFocus()
        NSApplication.shared.applicationIconImage = icon
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // macOS does not reap a process's children on exit, so without this every
        // `kubectl port-forward` survived Cmd-Q with its local port still bound — and
        // the next launch failed with "address already in use".
        PortForwardManager.shared.stopAll()
        return .terminateNow
    }
}
