import SwiftUI
import AppKit

struct SpotlightSearch: View {
    @Environment(AppViewModel.self) private var viewModel
    @Binding var isPresented: Bool
    @State private var query: String = ""
    @State private var selectedIndex: Int = 0
    @State private var computedResults: [SpotlightResult] = []
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Search input
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.title2)
                    .foregroundStyle(.secondary)

                TextField("Search resources, actions, namespaces...", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($isFocused)
                    .onSubmit { executeSelected() }
                    .onKeyPress(.upArrow) {
                        if selectedIndex > 0 { selectedIndex -= 1 }
                        return .handled
                    }
                    .onKeyPress(.downArrow) {
                        if selectedIndex < computedResults.count - 1 { selectedIndex += 1 }
                        return .handled
                    }
                    .onKeyPress(.escape) {
                        dismiss()
                        return .handled
                    }

                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Text("esc")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.gray.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            if !computedResults.isEmpty {
                Divider()

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(computedResults.indices, id: \.self) { index in
                                let result = computedResults[index]
                                SpotlightResultRow(
                                    result: result,
                                    isSelected: index == selectedIndex
                                )
                                .id(index)
                                .onTapGesture {
                                    selectedIndex = index
                                    executeSelected()
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 340)
                    .onChange(of: selectedIndex) { _, newValue in
                        withAnimation(.easeOut(duration: 0.1)) {
                            proxy.scrollTo(newValue, anchor: .center)
                        }
                    }
                }
            } else if !query.isEmpty {
                Divider()
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    Text("No results for \"\(query)\"")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 20)
            }

            // Hints when empty
            if query.isEmpty && computedResults.isEmpty {
                Divider()
                HStack(spacing: 16) {
                    hintBadge("pod name", desc: "search")
                    hintBadge("ns:kube-system", desc: "namespace")
                    hintBadge(":deploy", desc: "type")
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
        .background(.ultraThickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
        .frame(width: 560)
        .onAppear {
            query = ""
            selectedIndex = 0
            isFocused = true
            updateResults()
            // Preload all major resource types so search works across everything
            Task { await preloadAllResources() }
        }
        .onChange(of: query) { _, _ in
            selectedIndex = 0
            updateResults()
        }
    }

    private func hintBadge(_ text: String, desc: String) -> some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.system(.caption, design: .monospaced))
            Text(desc)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Preload all resources for cross-type search

    private func preloadAllResources() async {
        let typesToLoad: [ResourceType] = [.pods, .deployments, .services, .statefulSets, .daemonSets, .jobs, .cronJobs, .configMaps, .secrets, .nodes, .ingresses]
        for clusterId in viewModel.selectedClusterIds {
            guard let client = viewModel.activeClients[clusterId] else { continue }
            // Load types that aren't already loaded (don't re-fetch current type)
            await withTaskGroup(of: Void.self) { group in
                for type in typesToLoad {
                    let ns = type.isNamespaced ? viewModel.selectedNamespace : nil
                    group.addTask {
                        do {
                            switch type {
                            case .pods where viewModel.pods[clusterId] == nil || viewModel.pods[clusterId]?.isEmpty == true:
                                let items = try await client.list(Pod.self, resourceType: .pods, namespace: ns)
                                await MainActor.run { viewModel.pods[clusterId] = items }
                            case .deployments where viewModel.deployments[clusterId] == nil || viewModel.deployments[clusterId]?.isEmpty == true:
                                let items = try await client.list(Deployment.self, resourceType: .deployments, namespace: ns)
                                await MainActor.run { viewModel.deployments[clusterId] = items }
                            case .services where viewModel.services[clusterId] == nil || viewModel.services[clusterId]?.isEmpty == true:
                                let items = try await client.list(Service.self, resourceType: .services, namespace: ns)
                                await MainActor.run { viewModel.services[clusterId] = items }
                            case .statefulSets where viewModel.statefulSets[clusterId] == nil || viewModel.statefulSets[clusterId]?.isEmpty == true:
                                let items = try await client.list(StatefulSet.self, resourceType: .statefulSets, namespace: ns)
                                await MainActor.run { viewModel.statefulSets[clusterId] = items }
                            case .daemonSets where viewModel.daemonSets[clusterId] == nil || viewModel.daemonSets[clusterId]?.isEmpty == true:
                                let items = try await client.list(DaemonSet.self, resourceType: .daemonSets, namespace: ns)
                                await MainActor.run { viewModel.daemonSets[clusterId] = items }
                            case .jobs where viewModel.jobs[clusterId] == nil || viewModel.jobs[clusterId]?.isEmpty == true:
                                let items = try await client.list(Job.self, resourceType: .jobs, namespace: ns)
                                await MainActor.run { viewModel.jobs[clusterId] = items }
                            case .cronJobs where viewModel.cronJobs[clusterId] == nil || viewModel.cronJobs[clusterId]?.isEmpty == true:
                                let items = try await client.list(CronJob.self, resourceType: .cronJobs, namespace: ns)
                                await MainActor.run { viewModel.cronJobs[clusterId] = items }
                            case .configMaps where viewModel.configMaps[clusterId] == nil || viewModel.configMaps[clusterId]?.isEmpty == true:
                                let items = try await client.list(ConfigMap.self, resourceType: .configMaps, namespace: ns)
                                await MainActor.run { viewModel.configMaps[clusterId] = items }
                            case .secrets where viewModel.secrets[clusterId] == nil || viewModel.secrets[clusterId]?.isEmpty == true:
                                let items = try await client.list(Secret.self, resourceType: .secrets, namespace: ns)
                                await MainActor.run { viewModel.secrets[clusterId] = items }
                            case .nodes where viewModel.nodes[clusterId] == nil || viewModel.nodes[clusterId]?.isEmpty == true:
                                let items = try await client.list(Node.self, resourceType: .nodes)
                                await MainActor.run { viewModel.nodes[clusterId] = items }
                            case .ingresses where viewModel.ingresses[clusterId] == nil || viewModel.ingresses[clusterId]?.isEmpty == true:
                                let items = try await client.list(Ingress.self, resourceType: .ingresses, namespace: ns)
                                await MainActor.run { viewModel.ingresses[clusterId] = items }
                            default: break
                            }
                        } catch {
                            // Silently skip — search just won't find resources from this type
                        }
                    }
                }
            }
            // Update search results after preload
            await MainActor.run { updateResults() }
        }
    }

    // MARK: - Update results explicitly

    private func updateResults() {
        if query.isEmpty {
            computedResults = defaultResults()
        } else {
            computedResults = searchResults(for: query)
        }
    }

    private func defaultResults() -> [SpotlightResult] {
        var items: [SpotlightResult] = [
            SpotlightResult(id: "action:refresh", icon: "arrow.clockwise", title: "Refresh", subtitle: "Reload current resources", category: .action),
            SpotlightResult(id: "action:terminal", icon: "terminal", title: "Toggle Terminal", subtitle: "Cmd+Shift+T", category: .action),
            SpotlightResult(id: "action:overview", icon: "gauge.with.dots.needle.33percent", title: "Cluster Overview", subtitle: "Dashboard", category: .action),
        ]
        for type in ResourceType.allCases.prefix(8) {
            items.append(SpotlightResult(id: "type:\(type.rawValue)", icon: type.systemImage, title: type.displayName, subtitle: "Switch view", category: .resourceType))
        }
        return items
    }

    private func searchResults(for query: String) -> [SpotlightResult] {
        var results: [SpotlightResult] = []
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return defaultResults() }

        // Parse filters
        var nameFilter = q
        var nsFilter: String? = nil
        var typeFilter: ResourceType? = nil

        if q.hasPrefix("ns:") {
            let rest = String(q.dropFirst(3))
            let parts = rest.split(separator: " ", maxSplits: 1)
            nsFilter = String(parts.first ?? "")
            nameFilter = parts.count > 1 ? String(parts[1]) : ""
        } else if q.hasPrefix(":") {
            let typeName = String(q.dropFirst())
            typeFilter = ResourceType.allCases.first {
                $0.displayName.lowercased().hasPrefix(typeName) || $0.resource.hasPrefix(typeName)
            }
            nameFilter = ""
        }

        // Resource types
        if nsFilter == nil && typeFilter == nil {
            for type in ResourceType.allCases {
                if type.displayName.lowercased().contains(q) || type.resource.contains(q) {
                    results.append(SpotlightResult(id: "type:\(type.rawValue)", icon: type.systemImage, title: type.displayName, subtitle: "Switch view", category: .resourceType))
                }
            }
        }

        // Namespaces
        if nsFilter == nil && typeFilter == nil {
            var seen = Set<String>()
            for (_, nsList) in viewModel.availableNamespaces {
                for ns in nsList where ns.lowercased().contains(q) && !seen.contains(ns) {
                    seen.insert(ns)
                    results.append(SpotlightResult(id: "ns:\(ns)", icon: "folder", title: ns, subtitle: "Switch namespace", category: .namespace))
                }
            }
        }

        // Resources from current loaded data
        for clusterId in viewModel.selectedClusterIds {
            if let typeFilter = typeFilter {
                addResources(from: clusterId, type: typeFilter, nameFilter: nameFilter, nsFilter: nsFilter, to: &results)
            } else {
                // Search across all loaded types
                for type in ResourceType.allCases {
                    addResources(from: clusterId, type: type, nameFilter: nameFilter.isEmpty ? q : nameFilter, nsFilter: nsFilter, to: &results)
                    if results.count > 15 { break }
                }
            }
        }

        // CRDs
        if nsFilter == nil && typeFilter == nil {
            for crd in viewModel.discoveredCRDs {
                if crd.kind.lowercased().contains(q) || crd.plural.lowercased().contains(q) {
                    results.append(SpotlightResult(id: "crd:\(crd.id)", icon: "puzzlepiece.extension", title: crd.displayName, subtitle: crd.group, category: .crd, crd: crd))
                }
            }
        }

        // Actions
        let actions: [(String, String, String, String)] = [
            ("Refresh", "arrow.clockwise", "refresh", "Reload resources"),
            ("Terminal", "terminal", "terminal", "Toggle terminal"),
            ("Overview", "gauge.with.dots.needle.33percent", "overview", "Cluster dashboard"),
        ]
        for (name, icon, id, sub) in actions {
            if name.lowercased().contains(q) {
                results.append(SpotlightResult(id: "action:\(id)", icon: icon, title: name, subtitle: sub, category: .action))
            }
        }

        return Array(results.prefix(20))
    }

    private func addResources(from clusterId: String, type: ResourceType, nameFilter: String, nsFilter: String?, to results: inout [SpotlightResult]) {
        func search<T: K8sResource>(_ items: [T]?) {
            guard let items = items else { return }
            for item in items {
                if results.count > 18 { return }
                let nameMatch = nameFilter.isEmpty || item.name.lowercased().contains(nameFilter)
                let nsMatch = nsFilter == nil || (item.metadata.namespace?.lowercased().contains(nsFilter!) ?? false)
                if nameMatch && nsMatch {
                    let rid = ResourceIdentifier(clusterId: clusterId, resourceType: type, name: item.name, namespace: item.metadata.namespace)
                    let sub = [item.metadata.namespace, type.displayName].compactMap { $0 }.joined(separator: " · ")
                    let resultId = "res:\(type.rawValue):\(item.metadata.namespace ?? ""):\(item.name)"
                    if !results.contains(where: { $0.id == resultId }) {
                        results.append(SpotlightResult(id: resultId, icon: type.systemImage, title: item.name, subtitle: sub, category: .resource, resourceId: rid))
                    }
                }
            }
        }

        switch type {
        case .pods: search(viewModel.pods[clusterId])
        case .deployments: search(viewModel.deployments[clusterId])
        case .services: search(viewModel.services[clusterId])
        case .nodes: search(viewModel.nodes[clusterId])
        case .statefulSets: search(viewModel.statefulSets[clusterId])
        case .daemonSets: search(viewModel.daemonSets[clusterId])
        case .replicaSets: search(viewModel.replicaSets[clusterId])
        case .jobs: search(viewModel.jobs[clusterId])
        case .cronJobs: search(viewModel.cronJobs[clusterId])
        case .configMaps: search(viewModel.configMaps[clusterId])
        case .secrets: search(viewModel.secrets[clusterId])
        default: break
        }
    }

    // MARK: - Execute

    private func executeSelected() {
        guard selectedIndex < computedResults.count else { return }
        let result = computedResults[selectedIndex]

        switch result.category {
        case .action:
            switch result.id {
            case "action:refresh":
                Task { await viewModel.refresh() }
            case "action:terminal":
                NotificationCenter.default.post(name: .toggleTerminal, object: nil)
            case "action:overview":
                viewModel.showClusterOverview = true
            default: break
            }

        case .resourceType:
            let raw = result.id.replacingOccurrences(of: "type:", with: "")
            if let type = ResourceType(rawValue: raw) {
                viewModel.selectBuiltInType(type)
                Task { await viewModel.refresh() }
            }

        case .namespace:
            let ns = result.id.replacingOccurrences(of: "ns:", with: "")
            viewModel.selectedNamespace = ns
            Task { await viewModel.refresh() }

        case .resource:
            if let rid = result.resourceId {
                viewModel.selectBuiltInType(rid.resourceType)
                Task { await viewModel.refresh() }
                // Delay selection to let the list populate
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    NotificationCenter.default.post(name: .selectResource, object: rid)
                }
            }

        case .crd:
            if let crd = result.crd {
                viewModel.selectCRD(crd)
            }
        }

        dismiss()
    }

    private func dismiss() {
        isPresented = false
        query = ""
        computedResults = []
    }
}

// MARK: - Result Row

struct SpotlightResultRow: View {
    let result: SpotlightResult
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: result.icon)
                .font(.body)
                .foregroundStyle(isSelected ? .white : .secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text(result.title)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundStyle(isSelected ? .white : .primary)
                    .lineLimit(1)
                Text(result.subtitle)
                    .font(.caption)
                    .foregroundStyle(isSelected ? .white.opacity(0.7) : .secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(result.category.label)
                .font(.system(size: 9))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(isSelected ? Color.white.opacity(0.2) : Color.gray.opacity(0.15))
                .clipShape(Capsule())
                .foregroundStyle(isSelected ? Color.white.opacity(0.8) : Color.gray)

            if isSelected {
                Text("↵")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor : Color.clear)
        .contentShape(Rectangle())
    }
}

// MARK: - Data

struct SpotlightResult: Identifiable {
    let id: String
    let icon: String
    let title: String
    let subtitle: String
    let category: Category
    var resourceId: ResourceIdentifier? = nil
    var crd: CRDDefinition? = nil

    enum Category {
        case action, resourceType, namespace, resource, crd

        var label: String {
            switch self {
            case .action: return "Action"
            case .resourceType: return "Type"
            case .namespace: return "Namespace"
            case .resource: return "Resource"
            case .crd: return "CRD"
            }
        }
    }
}

extension Notification.Name {
    static let toggleTerminal = Notification.Name("toggleTerminal")
    static let selectResource = Notification.Name("selectResource")
}
