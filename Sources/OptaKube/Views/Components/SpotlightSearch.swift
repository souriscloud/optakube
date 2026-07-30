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
        // Snapshot main-actor state once. Doing this inside a TaskGroup's nonisolated
        // closure (as `where` clauses) tripped Swift-6 main-actor-isolation warnings.
        let clusterIds = viewModel.selectedClusterIds
        let selectedNs = viewModel.selectedNamespace
        let clients = viewModel.activeClients
        let already = loadedTypes(clusterIds: clusterIds, types: typesToLoad)

        for clusterId in clusterIds {
            guard let client = clients[clusterId] else { continue }
            await withTaskGroup(of: Void.self) { group in
                for type in typesToLoad {
                    if already.contains("\(clusterId)/\(type.rawValue)") { continue }
                    let ns = type.isNamespaced ? selectedNs : nil
                    group.addTask {
                        await loadType(type, clusterId: clusterId, client: client, namespace: ns)
                    }
                }
            }
            await MainActor.run { updateResults() }
        }
    }

    /// Snapshot which (cluster, type) pairs already have data, so the nonisolated
    /// preload tasks don't have to read `viewModel.*` from off the main actor.
    private func loadedTypes(clusterIds: Set<String>, types: [ResourceType]) -> Set<String> {
        var out = Set<String>()
        for clusterId in clusterIds {
            for type in types {
                let hasData: Bool
                switch type {
                case .pods: hasData = !(viewModel.pods[clusterId]?.isEmpty ?? true)
                case .deployments: hasData = !(viewModel.deployments[clusterId]?.isEmpty ?? true)
                case .services: hasData = !(viewModel.services[clusterId]?.isEmpty ?? true)
                case .statefulSets: hasData = !(viewModel.statefulSets[clusterId]?.isEmpty ?? true)
                case .daemonSets: hasData = !(viewModel.daemonSets[clusterId]?.isEmpty ?? true)
                case .jobs: hasData = !(viewModel.jobs[clusterId]?.isEmpty ?? true)
                case .cronJobs: hasData = !(viewModel.cronJobs[clusterId]?.isEmpty ?? true)
                case .configMaps: hasData = !(viewModel.configMaps[clusterId]?.isEmpty ?? true)
                case .secrets: hasData = !(viewModel.secrets[clusterId]?.isEmpty ?? true)
                case .nodes: hasData = !(viewModel.nodes[clusterId]?.isEmpty ?? true)
                case .ingresses: hasData = !(viewModel.ingresses[clusterId]?.isEmpty ?? true)
                default: hasData = true
                }
                if hasData { out.insert("\(clusterId)/\(type.rawValue)") }
            }
        }
        return out
    }

    private nonisolated func loadType(_ type: ResourceType, clusterId: String, client: K8sAPIClient, namespace: String?) async {
        do {
            switch type {
            case .pods:
                let items = try await client.list(Pod.self, resourceType: .pods, namespace: namespace)
                await MainActor.run { viewModel.pods[clusterId] = items }
            case .deployments:
                let items = try await client.list(Deployment.self, resourceType: .deployments, namespace: namespace)
                await MainActor.run { viewModel.deployments[clusterId] = items }
            case .services:
                let items = try await client.list(Service.self, resourceType: .services, namespace: namespace)
                await MainActor.run { viewModel.services[clusterId] = items }
            case .statefulSets:
                let items = try await client.list(StatefulSet.self, resourceType: .statefulSets, namespace: namespace)
                await MainActor.run { viewModel.statefulSets[clusterId] = items }
            case .daemonSets:
                let items = try await client.list(DaemonSet.self, resourceType: .daemonSets, namespace: namespace)
                await MainActor.run { viewModel.daemonSets[clusterId] = items }
            case .jobs:
                let items = try await client.list(Job.self, resourceType: .jobs, namespace: namespace)
                await MainActor.run { viewModel.jobs[clusterId] = items }
            case .cronJobs:
                let items = try await client.list(CronJob.self, resourceType: .cronJobs, namespace: namespace)
                await MainActor.run { viewModel.cronJobs[clusterId] = items }
            case .configMaps:
                let items = try await client.list(ConfigMap.self, resourceType: .configMaps, namespace: namespace)
                await MainActor.run { viewModel.configMaps[clusterId] = items }
            case .secrets:
                let items = try await client.list(Secret.self, resourceType: .secrets, namespace: namespace)
                await MainActor.run { viewModel.secrets[clusterId] = items }
            case .nodes:
                let items = try await client.list(Node.self, resourceType: .nodes)
                await MainActor.run { viewModel.nodes[clusterId] = items }
            case .ingresses:
                let items = try await client.list(Ingress.self, resourceType: .ingresses, namespace: namespace)
                await MainActor.run { viewModel.ingresses[clusterId] = items }
            default: break
            }
        } catch {
            // Silently skip — search just won't find resources from this type
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
        var items: [SpotlightResult] = []

        // Recents first — only those whose cluster is currently active so we don't
        // surface dead entries from kubeconfigs the user has since removed.
        let active = viewModel.selectedClusterIds
        let recents = RecentsStore.shared.all().filter { active.contains($0.clusterId) }
        for entry in recents.prefix(5) {
            guard let type = entry.resourceType else { continue }
            let rid = ResourceIdentifier(clusterId: entry.clusterId, resourceType: type, name: entry.name, namespace: entry.namespace)
            let ns = entry.namespace.map { "\($0) · " } ?? ""
            items.append(SpotlightResult(
                id: "recent:\(entry.id)",
                icon: "clock.arrow.circlepath",
                title: entry.name,
                subtitle: "\(ns)\(type.displayName) (recent)",
                category: .resource,
                resourceId: rid
            ))
        }

        items.append(contentsOf: [
            SpotlightResult(id: "action:refresh", icon: "arrow.clockwise", title: "Refresh", subtitle: "Reload current resources", category: .action),
            SpotlightResult(id: "action:terminal", icon: "terminal", title: "Toggle Terminal", subtitle: "Cmd+Shift+T", category: .action),
            SpotlightResult(id: "action:overview", icon: "gauge.with.dots.needle.33percent", title: "Cluster Overview", subtitle: "Dashboard", category: .action),
        ])
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
        // The remaining 21 fell into `default: break`, so ⌘K never matched them by name —
        // and typing `:ingress` set the type filter and then returned nothing at all.
        case .ingresses: search(viewModel.ingresses[clusterId])
        case .ingressClasses: search(viewModel.ingressClasses[clusterId])
        case .persistentVolumes: search(viewModel.persistentVolumes[clusterId])
        case .persistentVolumeClaims: search(viewModel.persistentVolumeClaims[clusterId])
        case .networkPolicies: search(viewModel.networkPolicies[clusterId])
        case .serviceAccounts: search(viewModel.serviceAccounts[clusterId])
        case .horizontalPodAutoscalers: search(viewModel.horizontalPodAutoscalers[clusterId])
        case .namespaces: search(viewModel.namespaces[clusterId])
        case .endpoints: search(viewModel.endpoints[clusterId])
        case .roles: search(viewModel.roles[clusterId])
        case .roleBindings: search(viewModel.roleBindings[clusterId])
        case .clusterRoles: search(viewModel.clusterRoles[clusterId])
        case .clusterRoleBindings: search(viewModel.clusterRoleBindings[clusterId])
        case .storageClasses: search(viewModel.storageClasses[clusterId])
        case .resourceQuotas: search(viewModel.resourceQuotas[clusterId])
        case .podDisruptionBudgets: search(viewModel.podDisruptionBudgets[clusterId])
        case .limitRanges: search(viewModel.limitRanges[clusterId])
        case .priorityClasses: search(viewModel.priorityClasses[clusterId])
        case .leases: search(viewModel.leases[clusterId])
        case .mutatingWebhookConfigurations: search(viewModel.mutatingWebhookConfigurations[clusterId])
        case .validatingWebhookConfigurations: search(viewModel.validatingWebhookConfigurations[clusterId])
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
                RecentsStore.shared.record(resource: rid)
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
    static let openFullLogs = Notification.Name("openFullLogs")
    static let openPodExec = Notification.Name("openPodExec")
}
