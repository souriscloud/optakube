import SwiftUI
import AppKit
import SwiftTerm

struct EmbeddedTerminal: View {
    let kubeconfigPath: String?
    let contextName: String
    let namespace: String

    var body: some View {
        SwiftTermView(
            kubeconfigPath: kubeconfigPath,
            contextName: contextName,
            namespace: namespace
        )
    }
}

// MARK: - NSViewRepresentable wrapping SwiftTerm's LocalProcessTerminalView

struct SwiftTermView: NSViewRepresentable {
    let kubeconfigPath: String?
    let contextName: String
    let namespace: String

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

        let shell = env["SHELL"] ?? "/bin/zsh"

        // Build an init file that sets up kubectl context
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
            // Fish uses --init-command
            shellArgs = ["--init-command", setupCmds]
            termView.startProcess(executable: shell, args: shellArgs, environment: envPairs, execName: "fish")
        } else {
            termView.startProcess(executable: shell, args: shellArgs, environment: envPairs, execName: shell)
        }

        return termView
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {
        // Nothing to update — the terminal runs independently
    }

    static func dismantleNSView(_ nsView: LocalProcessTerminalView, coordinator: ()) {
        // SwiftTerm handles cleanup when the view is removed
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
