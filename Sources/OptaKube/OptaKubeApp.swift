import SwiftUI
import AppKit
import Sparkle

@main
struct OptaKubeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.openWindow) private var openWindow
    // Only init Sparkle when running in a proper .app bundle (has CFBundleIdentifier)
    private let updaterController: SPUStandardUpdaterController? = {
        if Bundle.main.bundleIdentifier != nil {
            return SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        }
        return nil
    }()

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
            // About
            CommandGroup(replacing: .appInfo) {
                Button("About OptaKube") {
                    openWindow(id: "about")
                }
                if let updater = updaterController {
                    Divider()
                    Button("Check for Updates...") {
                        updater.updater.checkForUpdates()
                    }
                }
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
        }

        // Menu bar icon — uses cube symbol (matches app icon), supports macOS tinting
        MenuBarExtra("OptaKube", systemImage: "square.stack.3d.up") {
            PortForwardMenuBarView()
        }

        Settings {
            SettingsView()
        }

        // About window
        Window("About OptaKube", id: "about") {
            AboutView()
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)
    }

    private func switchResourceType(_ type: ResourceType) {
        for (_, vm) in WindowManager.shared.activeWindows {
            vm.selectBuiltInType(type)
            Task { await vm.refresh() }
            break
        }
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
                ProgressView("Connecting...")
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

        // Fallback: generate a high-quality icon programmatically
        let size: CGFloat = 512
        let icon = NSImage(size: NSSize(width: size, height: size))
        icon.lockFocus()
        guard let ctx = NSGraphicsContext.current?.cgContext else { icon.unlockFocus(); return }

        let rect = CGRect(x: 0, y: 0, width: size, height: size)
        let r = size * 0.22
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil))
        ctx.clip()

        // Blue gradient
        let colors = [CGColor(red: 0.25, green: 0.55, blue: 1.0, alpha: 1.0),
                      CGColor(red: 0.12, green: 0.32, blue: 0.85, alpha: 1.0)] as CFArray
        let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
        ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])

        // Cube wireframe
        let cx = size / 2, cy = size / 2, sz = size * 0.28
        ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
        ctx.setLineWidth(size * 0.02)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        let top = CGPoint(x: cx, y: cy - sz * 0.65)
        let mid = CGPoint(x: cx, y: cy + sz * 0.05)
        let bot = CGPoint(x: cx, y: cy + sz * 0.75)
        let left = CGPoint(x: cx - sz * 0.7, y: cy - sz * 0.25)
        let right = CGPoint(x: cx + sz * 0.7, y: cy - sz * 0.25)
        let botLeft = CGPoint(x: cx - sz * 0.7, y: cy + sz * 0.45)
        let botRight = CGPoint(x: cx + sz * 0.7, y: cy + sz * 0.45)

        // Faces
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.15))
        ctx.move(to: top); ctx.addLine(to: right); ctx.addLine(to: mid); ctx.addLine(to: left); ctx.closePath(); ctx.fillPath()
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.08))
        ctx.move(to: left); ctx.addLine(to: mid); ctx.addLine(to: bot); ctx.addLine(to: botLeft); ctx.closePath(); ctx.fillPath()
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.04))
        ctx.move(to: right); ctx.addLine(to: mid); ctx.addLine(to: bot); ctx.addLine(to: botRight); ctx.closePath(); ctx.fillPath()

        // Edges
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
        .terminateNow
    }
}
