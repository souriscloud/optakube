import SwiftUI
import UniformTypeIdentifiers

struct WelcomeWindow: View {
    @Environment(\.openWindow) private var openWindow
    private var windowManager = WindowManager.shared
    @State private var store = ClusterStore.shared
    @State private var selectedClusterIds: Set<String> = []
    @State private var isScanning = false
    @State private var showFileImporter = false
    @State private var showDirImporter = false
    @State private var testResults: [String: ConnectionTestResult] = [:]

    enum ConnectionTestResult {
        case testing
        case success(version: String)
        case failure(String)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            clusterList
            Divider()
            importSection
            Divider()
            footer
        }
        .frame(width: 680, height: 560)
        .onAppear {
            if store.availableConnections.isEmpty {
                Task { await scanForClusters() }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 48))
                .foregroundStyle(.blue)
                .padding(.top, 24)

            Text("Welcome to OptaKube")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Select the clusters you want to connect to")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.bottom, 16)
        }
    }

    // MARK: - Cluster List

    private var clusterList: some View {
        Group {
            if isScanning {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Scanning for Kubernetes clusters...")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.availableConnections.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("No clusters found")
                        .font(.headline)
                    Text("Import a kubeconfig file or directory to get started")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(store.availableConnections) { connection in
                            ClusterConnectionRow(
                                connection: connection,
                                isSelected: selectedClusterIds.contains(connection.id),
                                testResult: testResults[connection.id],
                                onToggle: { toggleSelection(connection) },
                                onTest: { Task { await testConnection(connection) } }
                            )
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Import Section

    private var importSection: some View {
        HStack(spacing: 12) {
            Button {
                showFileImporter = true
            } label: {
                Label("Import Kubeconfig", systemImage: "doc.badge.plus")
            }

            Button {
                showDirImporter = true
            } label: {
                Label("Import Directory", systemImage: "folder.badge.plus")
            }

            Spacer()

            Button {
                Task { await scanForClusters() }
            } label: {
                Label("Rescan", systemImage: "arrow.clockwise")
            }
            .disabled(isScanning)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.data, .yaml, .text], allowsMultipleSelection: true) { result in
            handleFileImport(result)
        }
        .fileImporter(isPresented: $showDirImporter, allowedContentTypes: [.folder], allowsMultipleSelection: true) { result in
            handleDirImport(result)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Text("\(selectedClusterIds.count) cluster\(selectedClusterIds.count == 1 ? "" : "s") selected")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            Button("Connect") {
                connectAndOpenWindow()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(selectedClusterIds.isEmpty)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    // MARK: - Actions

    private func connectAndOpenWindow() {
        // One window per cluster
        let connectionsToOpen = store.availableConnections.filter { selectedClusterIds.contains($0.id) }

        for conn in connectionsToOpen {
            let windowId = windowManager.createClusterWindow(clusterIds: [conn.id])
            openWindow(id: "cluster", value: windowId)

            if let vm = windowManager.viewModel(for: windowId) {
                Task {
                    await vm.connect(to: conn)
                }
            }
        }

        // Hide the welcome window
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            for window in NSApplication.shared.windows {
                if window.identifier?.rawValue.contains("welcome") == true ||
                   window.title == "OptaKube" {
                    window.orderOut(nil)
                    break
                }
            }
        }

        selectedClusterIds.removeAll()
    }

    private func toggleSelection(_ connection: ClusterConnection) {
        if selectedClusterIds.contains(connection.id) {
            selectedClusterIds.remove(connection.id)
        } else {
            selectedClusterIds.insert(connection.id)
        }
    }

    private func scanForClusters() async {
        isScanning = true
        await store.discoverClusters()
        isScanning = false
    }

    private func testConnection(_ connection: ClusterConnection) async {
        testResults[connection.id] = .testing
        let client = K8sAPIClient(connection: connection)
        do {
            let version = try await client.getServerVersion()
            testResults[connection.id] = .success(version: version)
        } catch {
            testResults[connection.id] = .failure(error.localizedDescription)
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        guard let urls = try? result.get() else { return }
        store.addKubeConfigPaths(urls.map { $0.path })
        Task { await scanForClusters() }
    }

    private func handleDirImport(_ result: Result<[URL], Error>) {
        guard let urls = try? result.get(), let dir = urls.first else { return }
        store.addKubeConfigDirectory(dir.path)
        Task { await scanForClusters() }
    }
}

// MARK: - Cluster Row

struct ClusterConnectionRow: View {
    let connection: ClusterConnection
    let isSelected: Bool
    let testResult: WelcomeWindow.ConnectionTestResult?
    let onToggle: () -> Void
    let onTest: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isSelected ? .blue : .secondary)
                .onTapGesture { onToggle() }

            VStack(alignment: .leading, spacing: 3) {
                Text(connection.name)
                    .font(.body)
                    .fontWeight(.medium)

                HStack(spacing: 8) {
                    Label(serverHost, systemImage: "server.rack")
                    Label(authLabel, systemImage: authIcon)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            if let result = testResult {
                testResultView(result)
            }

            Button("Test") { onTest() }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(testResult.isTestingOrNil)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture { onToggle() }
        .background(isSelected ? Color.accentColor.opacity(0.06) : Color.clear)
    }

    @ViewBuilder
    private func testResultView(_ result: WelcomeWindow.ConnectionTestResult) -> some View {
        switch result {
        case .testing:
            ProgressView().controlSize(.small)
        case .success(let version):
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("v\(version)").font(.caption).foregroundStyle(.secondary)
            }
        case .failure(let msg):
            HStack(spacing: 4) {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                Text(msg).font(.caption).foregroundStyle(.red).lineLimit(1).frame(maxWidth: 150)
            }
        }
    }

    private var serverHost: String {
        URL(string: connection.server)?.host ?? connection.server
    }

    private var authLabel: String {
        switch connection.authInfo {
        case .token: return "Token"
        case .clientCertificate: return "Certificate"
        case .exec: return "Exec"
        case .none: return "None"
        }
    }

    private var authIcon: String {
        switch connection.authInfo {
        case .token: return "key"
        case .clientCertificate: return "lock.shield"
        case .exec: return "terminal"
        case .none: return "questionmark.circle"
        }
    }
}

private extension Optional where Wrapped == WelcomeWindow.ConnectionTestResult {
    var isTestingOrNil: Bool {
        if case .testing = self { return true }
        return false
    }
}

extension UTType {
    static var yaml: UTType { UTType(filenameExtension: "yaml") ?? .data }
}
