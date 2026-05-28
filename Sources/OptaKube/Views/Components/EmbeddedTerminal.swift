import SwiftUI
import AppKit
import SwiftTerm

/// Lets actions outside the terminal view (e.g. "Exec Shell" on a pod) type commands
/// into the running shell's PTY. The bridge holds a weak reference to the active
/// terminal view; if no terminal is attached when a command arrives, the command is
/// queued and flushed once a terminal attaches.
@MainActor
final class TerminalBridge {
    static let shared = TerminalBridge()
    private weak var view: LocalProcessTerminalView?
    private var queue: [String] = []

    func attach(_ v: LocalProcessTerminalView) {
        view = v
        guard !queue.isEmpty else { return }
        // Give the shell a moment to source rc files and reach the prompt before
        // delivering buffered keystrokes — otherwise the rc's own output and our
        // input interleave confusingly.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.flush()
        }
    }

    func detach(_ v: LocalProcessTerminalView) {
        if view === v { view = nil }
    }

    /// Type a command into the terminal, then press Enter. We send the command and the
    /// CR in two separate writes with a small gap: fish/zsh-with-shell-integration
    /// heuristically detect a single-write burst as a paste, dropping the trailing CR
    /// into the edit buffer instead of submitting. Two writes look like "typed text"
    /// followed by an "Enter keystroke" and execute the command.
    func runCommand(_ cmd: String) {
        let trimmed = (cmd.hasSuffix("\n") || cmd.hasSuffix("\r")) ? String(cmd.dropLast()) : cmd
        queue.append(trimmed)
        if view != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.flush()
            }
        }
    }

    private func flush() {
        guard let v = view else { return }
        let pending = queue
        queue.removeAll()
        for cmd in pending {
            // Wrap in DEC bracketed-paste markers so the shell unambiguously treats the
            // text as pasted content (placed in edit buffer, not executed). Then a
            // separate CR keystroke, sent after the paste-end marker, is the real Enter.
            var bytes: [UInt8] = []
            bytes.append(contentsOf: [0x1b, 0x5b, 0x32, 0x30, 0x30, 0x7e]) // ESC [ 2 0 0 ~
            bytes.append(contentsOf: Array(cmd.utf8))
            bytes.append(contentsOf: [0x1b, 0x5b, 0x32, 0x30, 0x31, 0x7e]) // ESC [ 2 0 1 ~
            v.process.send(data: ArraySlice(bytes))
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak v] in
                v?.process.send(data: ArraySlice([0x0D]))
            }
        }
    }
}

struct EmbeddedTerminal: View {
    let kubeconfigPath: String?
    let contextName: String
    let namespace: String
    /// If set, the terminal runs this command via the user's login shell (`shell -l -c …`)
    /// instead of dropping into an interactive shell. Used by Exec-into-Pod.
    let runCommand: String?

    init(kubeconfigPath: String?, contextName: String, namespace: String, runCommand: String? = nil) {
        self.kubeconfigPath = kubeconfigPath
        self.contextName = contextName
        self.namespace = namespace
        self.runCommand = runCommand
    }

    var body: some View {
        SwiftTermView(
            kubeconfigPath: kubeconfigPath,
            contextName: contextName,
            namespace: namespace,
            runCommand: runCommand
        )
    }
}

// MARK: - NSViewRepresentable wrapping SwiftTerm's LocalProcessTerminalView

struct SwiftTermView: NSViewRepresentable {
    let kubeconfigPath: String?
    let contextName: String
    let namespace: String
    let runCommand: String?

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let termView = LocalProcessTerminalView(frame: .zero)
        let fontSize: CGFloat = CGFloat(UserDefaults.standard.double(forKey: "terminalFontSize").nonZero ?? 13)
        termView.font = resolveTerminalFont(size: fontSize)
        termView.nativeBackgroundColor = NSColor(calibratedRed: 0.12, green: 0.12, blue: 0.14, alpha: 1.0)
        termView.nativeForegroundColor = NSColor(calibratedRed: 0.9, green: 0.9, blue: 0.9, alpha: 1.0)

        // Build environment
        var env = ProcessInfo.processInfo.environment
        if let kc = kubeconfigPath {
            env["KUBECONFIG"] = kc
        }
        env["TERM"] = "xterm-256color"
        env["LANG"] = "en_US.UTF-8"
        let envPairs = env.map { "\($0.key)=\($0.value)" }

        let shell = resolvePreferredShell(env: env)

        // Command-mode: just run the given command via the user's login shell so PATH from
        // .zprofile/.fish_profile is picked up (needed for kubectl, aws, etc. when launched
        // from Finder where the bundle inherits only a minimal PATH).
        if let cmd = runCommand {
            let execName = (shell as NSString).lastPathComponent
            termView.startProcess(executable: shell, args: ["-l", "-c", cmd], environment: envPairs, execName: execName)
            TerminalBridge.shared.attach(termView)
            return termView
        }

        // Interactive: set up kubectl context inside the shell.
        let setupCmds = """
        kubectl config use-context '\(contextName)' 2>/dev/null
        kubectl config set-context --current --namespace='\(namespace)' 2>/dev/null
        printf '\\033[1;36m● OptaKube — \(contextName) (ns: \(namespace))\\033[0m\\n\\n'
        """

        var shellArgs = [String]()

        if shell.hasSuffix("zsh") {
            let tmpDir = "/tmp/optakube-zsh-\(ProcessInfo.processInfo.processIdentifier)-\(Int.random(in: 1000...9999))"
            try? FileManager.default.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
            let home = env["HOME"] ?? NSHomeDirectory()
            let zshrc = """
            [[ -f \(home)/.zshrc ]] && source \(home)/.zshrc
            \(setupCmds)
            """
            try? zshrc.write(toFile: "\(tmpDir)/.zshrc", atomically: true, encoding: .utf8)
            // Set ZDOTDIR in the environment
            var envWithZdotdir = envPairs
            envWithZdotdir.append("ZDOTDIR=\(tmpDir)")
            termView.startProcess(executable: shell, args: shellArgs, environment: envWithZdotdir, execName: "-zsh")
        } else if shell.hasSuffix("bash") {
            let tmpRC = "/tmp/optakube-bashrc-\(ProcessInfo.processInfo.processIdentifier)"
            let bashrc = """
            [[ -f ~/.bashrc ]] && source ~/.bashrc
            \(setupCmds)
            """
            try? bashrc.write(toFile: tmpRC, atomically: true, encoding: .utf8)
            shellArgs = ["--rcfile", tmpRC]
            termView.startProcess(executable: shell, args: shellArgs, environment: envPairs, execName: "-bash")
        } else if shell.hasSuffix("fish") {
            // --login so fish sources ~/.config/fish/config.fish AND login-only fragments
            // (AWS env vars often live there). --init-command runs once after init.
            shellArgs = ["--login", "--init-command", setupCmds]
            termView.startProcess(executable: shell, args: shellArgs, environment: envPairs, execName: "-fish")
        } else {
            termView.startProcess(executable: shell, args: shellArgs, environment: envPairs, execName: shell)
        }

        TerminalBridge.shared.attach(termView)
        return termView
    }

    /// Picks the shell to run inside the terminal. Priority:
    /// 1. Explicit user override (UserDefaults `terminalShellPath`)
    /// 2. Auto-detected fish if it's installed — `SHELL` from a Finder-launched .app
    ///    usually reflects `chsh`, so fish-via-rc users would otherwise never see it
    /// 3. `SHELL` env var
    /// 4. /bin/zsh fallback
    private func resolvePreferredShell(env: [String: String]) -> String {
        if let override = UserDefaults.standard.string(forKey: "terminalShellPath"),
           !override.isEmpty,
           FileManager.default.isExecutableFile(atPath: override) {
            return override
        }
        // Respect SHELL when fish is already configured via chsh
        let envShell = env["SHELL"]
        if let s = envShell, s.hasSuffix("/fish") { return s }
        // Otherwise opportunistically pick up an installed fish
        for path in ["/opt/homebrew/bin/fish", "/usr/local/bin/fish"] {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return envShell ?? "/bin/zsh"
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {
        // Nothing to update — the terminal runs independently
    }

    static func dismantleNSView(_ nsView: LocalProcessTerminalView, coordinator: ()) {
        Task { @MainActor in TerminalBridge.shared.detach(nsView) }
    }

    /// Resolve the best monospace font: user preference > detected nerd font > Menlo > system
    private func resolveTerminalFont(size: CGFloat) -> NSFont {
        // Check user preference
        if let preferred = UserDefaults.standard.string(forKey: "terminalFontName"),
           let font = NSFont(name: preferred, size: size) {
            return font
        }

        // Auto-detect installed nerd fonts (prefer Mono variants for terminal)
        let nerdFontCandidates = [
            "JetBrainsMonoNFM-Regular",      // JetBrains Mono Nerd Font Mono
            "JetBrainsMonoNF-Regular",        // JetBrains Mono Nerd Font
            "MesloLGSNFM-Regular",            // Meslo Nerd Font Mono
            "MesloLGMNFM-Regular",
            "HackNFM-Regular",                // Hack Nerd Font Mono
            "FiraCodeNFM-Reg",                // Fira Code Nerd Font Mono
            "CaskaydiaCoveNFM-Regular",       // Cascadia Code Nerd Font Mono
            "SauceCodeProNFM-Regular",        // Source Code Pro Nerd Font Mono
        ]

        for name in nerdFontCandidates {
            if let font = NSFont(name: name, size: size) {
                return font
            }
        }

        // Fallback: Menlo (ships with macOS, good glyph coverage) > system mono
        return NSFont(name: "Menlo-Regular", size: size)
            ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }
}

private extension Double {
    var nonZero: Double? { self > 0 ? self : nil }
}
