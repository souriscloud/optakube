import SwiftUI

struct MainWindow: View {
    @Environment(AppViewModel.self) private var viewModel
    @State private var selectedResource: ResourceIdentifier?
    @State private var showDetail: Bool = false
    @State private var showTerminal: Bool = false
    @State private var showSpotlight: Bool = false
    @State private var dismissedError: String?

    private struct ConnectionError: Equatable {
        let clusterName: String
        let message: String
    }

    private var connectionError: ConnectionError? {
        for conn in viewModel.activeConnections {
            if case .error(let msg) = viewModel.connectionStatuses[conn.id], msg != dismissedError {
                return ConnectionError(clusterName: conn.name, message: msg)
            }
        }
        return nil
    }

    var body: some View {
        @Bindable var vm = viewModel

        VStack(spacing: 0) {
            // Connection error banner
            if let errorConn = connectionError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.white)
                    Text(errorConn.message)
                        .font(.caption)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer()
                    Button("Retry") {
                        if let conn = viewModel.activeConnections.first(where: { viewModel.connectionStatuses[$0.id] == .error(errorConn.message) }) {
                            Task { await viewModel.connect(to: conn) }
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.white)
                    Button {
                        dismissedError = errorConn.message
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.red.gradient)
            }

            // Main content area
            NavigationSplitView {
                SidebarView()
                    .navigationSplitViewColumnWidth(min: 160, ideal: 200, max: 280)
            } detail: {
                if viewModel.showClusterOverview {
                    ClusterOverview()
                } else {
                    if showDetail, let resource = selectedResource {
                        // Resizable split: resource list + detail
                        HSplitView {
                            ResourceListView(selectedResource: $selectedResource)
                                .frame(minWidth: 300)

                            ResourceDetailView(resource: resource)
                                .frame(minWidth: 280, idealWidth: 420)
                        }
                    } else {
                        ResourceListView(selectedResource: $selectedResource)
                    }
                }
            }

            // Embedded terminal (bottom panel)
            if showTerminal, let conn = viewModel.activeConnections.first {
                Divider()
                EmbeddedTerminal(
                    kubeconfigPath: kubeconfigPathForConnection(conn),
                    contextName: conn.contextName,
                    namespace: viewModel.selectedNamespace ?? conn.defaultNamespace ?? "default"
                )
                .frame(minHeight: 120, idealHeight: 200, maxHeight: 350)
            }

            Divider()
            StatusBar(showTerminal: $showTerminal)
        }
        .searchable(text: $vm.searchText, prompt: "Filter resources...")
        .toolbar {
            ToolbarItemGroup(placement: .principal) {
                connectedClustersLabel
            }

            ToolbarItemGroup(placement: .primaryAction) {
                // Spotlight search
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { showSpotlight.toggle() }
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .keyboardShortcut("k", modifiers: .command)
                .help("Quick search (Cmd+K)")

                NamespacePicker()

                Button {
                    Task { await viewModel.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: .command)
                .help("Refresh")

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        showDetail.toggle()
                    }
                } label: {
                    Image(systemName: "sidebar.right")
                        .symbolVariant(showDetail ? .none : .slash)
                }
                .help(showDetail ? "Hide inspector" : "Show inspector")
                .keyboardShortcut("d", modifiers: .command)
                .disabled(selectedResource == nil && !showDetail)
            }
        }
        .onChange(of: selectedResource) { _, newValue in
            if newValue != nil && !showDetail {
                withAnimation(.easeInOut(duration: 0.15)) {
                    showDetail = true
                }
            }
        }
        .onAppear {
            viewModel.startAutoRefresh()
        }
        .onDisappear {
            viewModel.stopAutoRefresh()
            viewModel.saveState()
        }
        .onChange(of: viewModel.selectedResourceType) { _, _ in viewModel.saveState() }
        .onChange(of: viewModel.selectedNamespace) { _, _ in viewModel.saveState() }
        .overlay {
            if showSpotlight {
                // Dimmed backdrop
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture { showSpotlight = false }

                // Spotlight panel, positioned near top
                VStack {
                    SpotlightSearch(isPresented: $showSpotlight)
                        .padding(.top, 80)
                    Spacer()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleTerminal)) { _ in
            withAnimation(.easeInOut(duration: 0.15)) { showTerminal.toggle() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .selectResource)) { notif in
            if let rid = notif.object as? ResourceIdentifier {
                selectedResource = rid
                if !showDetail { withAnimation { showDetail = true } }
            }
        }
    }

    private var connectedClustersLabel: some View {
        return HStack(spacing: 6) {
            ForEach(viewModel.activeConnections) { conn in
                let custom = ClusterCustomizationStore.shared.get(for: conn.id)
                HStack(spacing: 4) {
                    Circle()
                        .fill(custom.color)
                        .frame(width: 7, height: 7)
                    Text(custom.displayName ?? conn.name)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .padding(.horizontal, 8)
        .frame(minWidth: 60, maxWidth: 220)
    }

    private func kubeconfigPathForConnection(_ conn: ClusterConnection) -> String? {
        let parts = conn.id.split(separator: ":", maxSplits: 1)
        return parts.count > 0 ? String(parts[0]) : nil
    }
}

struct ResourceIdentifier: Hashable {
    let clusterId: String
    let resourceType: ResourceType
    let name: String
    let namespace: String?
}
