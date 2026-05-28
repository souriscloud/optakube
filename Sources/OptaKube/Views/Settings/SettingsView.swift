import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            KubeConfigSettingsView()
                .tabItem {
                    Label("Kubeconfig", systemImage: "key")
                }

            AppearanceSettingsView()
                .tabItem {
                    Label("Appearance", systemImage: "paintbrush")
                }

            UpdatesSettingsView()
                .tabItem {
                    Label("Updates", systemImage: "arrow.down.circle")
                }
        }
        .frame(width: 500, height: 420)
    }
}

struct KubeConfigSettingsView: View {
    private var store = ClusterStore.shared
    @State private var newPath = ""
    @State private var newDir = ""

    var body: some View {
        Form {
            Section("Kubeconfig Files") {
                ForEach(store.kubeConfigPaths, id: \.self) { path in
                    HStack {
                        Text(path)
                            .font(.system(.body, design: .monospaced))
                        Spacer()
                        Button(role: .destructive) {
                            store.removeKubeConfigPath(path)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                }

                HStack {
                    TextField("Add kubeconfig path...", text: $newPath)
                        .textFieldStyle(.roundedBorder)
                    Button("Add") {
                        if !newPath.isEmpty {
                            store.addKubeConfigPaths([newPath])
                            newPath = ""
                        }
                    }
                }
            }

            Section("Kubeconfig Directories") {
                ForEach(store.kubeConfigDirs, id: \.self) { dir in
                    HStack {
                        Text(dir)
                            .font(.system(.body, design: .monospaced))
                        Spacer()
                        Button(role: .destructive) {
                            store.removeKubeConfigDirectory(dir)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                }

                HStack {
                    TextField("Add directory path...", text: $newDir)
                        .textFieldStyle(.roundedBorder)
                    Button("Add") {
                        if !newDir.isEmpty {
                            store.addKubeConfigDirectory(newDir)
                            newDir = ""
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct AppearanceSettingsView: View {
    @AppStorage("refreshInterval") private var refreshInterval = 10.0
    @AppStorage("maxLogLines") private var maxLogLines = 10000
    @AppStorage("terminalFontName") private var terminalFontName = ""
    @AppStorage("terminalFontSize") private var terminalFontSize = 13.0
    @AppStorage("terminalShellPath") private var terminalShellPath = ""

    var body: some View {
        Form {
            Section("Refresh") {
                Slider(value: $refreshInterval, in: 5...60, step: 5) {
                    Text("Auto-refresh interval: \(Int(refreshInterval))s")
                }
            }

            Section("Logs") {
                Stepper("Max log lines: \(maxLogLines)", value: $maxLogLines, in: 1000...100000, step: 1000)
            }

            Section("Terminal") {
                HStack {
                    Text("Font")
                    Spacer()
                    Picker("", selection: $terminalFontName) {
                        Text("Auto-detect").tag("")
                        ForEach(availableMonoFonts, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    .frame(width: 250)
                }

                Stepper("Font size: \(Int(terminalFontSize))pt", value: $terminalFontSize, in: 9...24, step: 1)

                HStack {
                    Text("Shell")
                    Spacer()
                    Picker("", selection: $terminalShellPath) {
                        Text("Auto-detect (prefers fish)").tag("")
                        ForEach(availableShells, id: \.self) { path in
                            Text(path).tag(path)
                        }
                    }
                    .frame(width: 250)
                }

                Text("Restart the terminal for changes to take effect.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var availableShells: [String] {
        let candidates = [
            "/opt/homebrew/bin/fish", "/usr/local/bin/fish",
            "/bin/zsh", "/bin/bash", "/bin/sh",
            "/opt/homebrew/bin/zsh", "/usr/local/bin/zsh",
            "/opt/homebrew/bin/bash", "/usr/local/bin/bash",
        ]
        return candidates.filter { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private var availableMonoFonts: [String] {
        let families = NSFontManager.shared.availableFontFamilies
        return families.filter { family in
            let lc = family.lowercased()
            return lc.contains("mono") || lc.contains("nerd") || lc.contains("code")
                || lc.contains("menlo") || lc.contains("consolas") || lc.contains("courier")
                || lc.contains("hack") || lc.contains("fira") || lc.contains("jetbrains")
                || lc.contains("meslo") || lc.contains("cascadia") || lc.contains("source code")
        }.sorted()
    }
}

struct UpdatesSettingsView: View {
    @AppStorage("updateChannel") private var channelRaw = UpdateChannel.release.rawValue
    @AppStorage("notifyPodRestarts") private var notifyPodRestarts = true

    private var channel: UpdateChannel {
        get { UpdateChannel(rawValue: channelRaw) ?? .release }
    }

    var body: some View {
        Form {
            Section("Update channel") {
                Picker("Channel", selection: $channelRaw) {
                    ForEach(UpdateChannel.allCases) { ch in
                        Text(ch.displayName).tag(ch.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                Text(channelInfo)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Check for Updates Now") {
                    UpdateController.shared.checkForUpdates(nil)
                }
                .disabled(!UpdateController.shared.isAvailable)
            }
            Section("Notifications") {
                Toggle("Notify on pod restart", isOn: $notifyPodRestarts)
                Text("Posts a system notification when a watched pod's restart count increases. Requires Notifications permission for OptaKube in System Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var channelInfo: String {
        switch channel {
        case .release: return "Stable releases only."
        case .beta: return "Pre-release builds. May include unfinished features or bugs."
        }
    }
}
