import SwiftUI

struct SidebarView: View {
    @Environment(AppViewModel.self) private var viewModel
    @State private var collapsedCategories: Set<String> = []
    @State private var collapsedCRDGroups: Set<String> = []
    @State private var sidebarSelection: ResourceType?

    var body: some View {
        List(selection: $sidebarSelection) {
            // Connected clusters (always visible, clickable for overview)
            Section("Connected") {
                ForEach(viewModel.activeConnections) { connection in
                    Button {
                        sidebarSelection = nil
                        viewModel.showClusterOverview = true
                        viewModel.selectedCRD = nil
                    } label: {
                        ClusterRow(
                            connection: connection,
                            status: viewModel.connectionStatuses[connection.id] ?? .connecting
                        )
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(viewModel.showClusterOverview ? Color.accentColor.opacity(0.15) : Color.clear)
                }
            }

            // Built-in resource categories (collapsible)
            ForEach(ResourceType.grouped, id: \.0) { category, types in
                Section(isExpanded: expansionBinding(for: category.rawValue, in: $collapsedCategories)) {
                    ForEach(types) { type in
                        Label(type.displayName, systemImage: type.systemImage)
                            .tag(type)
                    }
                } header: {
                    Text(category.rawValue)
                }
            }

            // CRD sections (collapsible, grouped by API group)
            if !viewModel.discoveredCRDs.isEmpty {
                let grouped = Dictionary(grouping: viewModel.discoveredCRDs) { $0.group }
                ForEach(grouped.keys.sorted(), id: \.self) { group in
                    Section(isExpanded: expansionBinding(for: group, in: $collapsedCRDGroups)) {
                        ForEach(grouped[group]!) { crd in
                            Button {
                                sidebarSelection = nil
                                viewModel.selectCRD(crd)
                            } label: {
                                HStack {
                                    Image(systemName: "puzzlepiece.extension")
                                        .foregroundStyle(.secondary)
                                    Text(crd.displayName)
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                            .padding(.vertical, 1)
                            .background(viewModel.selectedCRD == crd ? Color.accentColor.opacity(0.15) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    } header: {
                        Text(shortGroupName(group))
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .onAppear {
            // Sync initial selection
            if !viewModel.showClusterOverview && viewModel.selectedCRD == nil {
                sidebarSelection = viewModel.selectedResourceType
            }
        }
        .onChange(of: sidebarSelection) { _, newValue in
            guard let type = newValue else { return }
            viewModel.selectedCRD = nil
            viewModel.showClusterOverview = false
            if viewModel.selectedResourceType != type {
                viewModel.selectedResourceType = type
                Task { await viewModel.refresh() }
            } else if viewModel.showClusterOverview {
                // Coming back from overview to same type — just refresh
                Task { await viewModel.refresh() }
            }
        }
        // Sync sidebar when resource type changes externally (e.g. keyboard shortcuts)
        .onChange(of: viewModel.selectedResourceType) { _, newValue in
            if sidebarSelection != newValue && !viewModel.showClusterOverview {
                sidebarSelection = newValue
            }
        }
        .onChange(of: viewModel.showClusterOverview) { _, isOverview in
            if isOverview {
                sidebarSelection = nil
            }
        }
    }

    private func expansionBinding(for key: String, in collapsedSet: Binding<Set<String>>) -> Binding<Bool> {
        Binding(
            get: { !collapsedSet.wrappedValue.contains(key) },
            set: { isExpanded in
                if isExpanded {
                    collapsedSet.wrappedValue.remove(key)
                } else {
                    collapsedSet.wrappedValue.insert(key)
                }
            }
        )
    }

    private func shortGroupName(_ group: String) -> String {
        let parts = group.split(separator: ".")
        if parts.count > 2 {
            return parts.suffix(2).joined(separator: ".")
        }
        return group
    }
}

struct ClusterRow: View {
    let connection: ClusterConnection
    let status: ConnectionStatus
    @State private var showCustomize = false

    private var custom: ClusterCustomization {
        ClusterCustomizationStore.shared.get(for: connection.id)
    }

    var body: some View {
        HStack(spacing: 8) {
            // Color dot
            Circle()
                .fill(custom.color)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(custom.displayName ?? connection.name)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button("Customize...") { showCustomize = true }
        }
        .popover(isPresented: $showCustomize) {
            ClusterCustomizePopover(connectionId: connection.id, originalName: connection.name)
        }
    }

    private var statusText: String {
        switch status {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting..."
        case .connected(let version): return "v\(version)"
        case .error(let msg): return msg
        }
    }

    private var statusColor: Color {
        switch status {
        case .disconnected: return .gray
        case .connecting: return .orange
        case .connected: return .green
        case .error: return .red
        }
    }
}

struct ClusterCustomizePopover: View {
    let connectionId: String
    let originalName: String
    @State private var displayName: String = ""
    @State private var selectedColor: String = "blue"
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Customize Cluster")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text("Display Name").font(.caption).foregroundStyle(.secondary)
                TextField(originalName, text: $displayName)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Color").font(.caption).foregroundStyle(.secondary)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(24), spacing: 6), count: 6), spacing: 6) {
                    ForEach(ClusterCustomization.availableColors, id: \.name) { item in
                        Circle()
                            .fill(item.color)
                            .frame(width: 24, height: 24)
                            .overlay {
                                if selectedColor == item.name {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            }
                            .onTapGesture { selectedColor = item.name }
                    }
                }
            }

            HStack {
                Button("Reset") {
                    ClusterCustomizationStore.shared.reset(for: connectionId)
                    dismiss()
                }
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    let custom = ClusterCustomization(
                        displayName: displayName.isEmpty ? nil : displayName,
                        colorName: selectedColor
                    )
                    ClusterCustomizationStore.shared.set(custom, for: connectionId)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 260)
        .onAppear {
            let c = ClusterCustomizationStore.shared.get(for: connectionId)
            displayName = c.displayName ?? ""
            selectedColor = c.colorName ?? "blue"
        }
    }
}
