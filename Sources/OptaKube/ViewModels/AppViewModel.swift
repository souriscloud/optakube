import Foundation
import SwiftUI

// MARK: - Shared State (singleton, shared across all windows)

@Observable
final class ClusterStore {
    static let shared = ClusterStore()

    var availableConnections: [ClusterConnection] = []

    var kubeConfigPaths: [String] {
        get { UserDefaults.standard.stringArray(forKey: "kubeConfigPaths") ?? ["~/.kube/config"] }
        set { UserDefaults.standard.set(newValue, forKey: "kubeConfigPaths") }
    }

    var kubeConfigDirs: [String] {
        get { UserDefaults.standard.stringArray(forKey: "kubeConfigDirs") ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: "kubeConfigDirs") }
    }

    private let kubeConfigService = KubeConfigService()

    private init() {
        Task { await discoverClusters() }
    }

    func discoverClusters() async {
        var sources: [KubeConfigService.Source] = []
        for path in kubeConfigPaths { sources.append(.file(path)) }
        for dir in kubeConfigDirs { sources.append(.directory(dir)) }
        let connections = await kubeConfigService.loadConnections(from: sources)
        await MainActor.run { availableConnections = connections }
    }

    func addKubeConfigPaths(_ paths: [String]) {
        var current = kubeConfigPaths
        for path in paths where !current.contains(path) { current.append(path) }
        kubeConfigPaths = current
    }

    func addKubeConfigDirectory(_ dir: String) {
        var current = kubeConfigDirs
        if !current.contains(dir) { current.append(dir); kubeConfigDirs = current }
    }

    func removeKubeConfigPath(_ path: String) {
        kubeConfigPaths = kubeConfigPaths.filter { $0 != path }
    }

    func removeKubeConfigDirectory(_ dir: String) {
        kubeConfigDirs = kubeConfigDirs.filter { $0 != dir }
    }
}

// MARK: - Per-Window State

@Observable
final class AppViewModel: Identifiable {
    let id: String
    let store = ClusterStore.shared

    // Navigation state
    var showMainWindow: Bool = false

    // Per-window cluster/view state
    var activeClients: [String: K8sAPIClient] = [:]
    var connectionStatuses: [String: ConnectionStatus] = [:]
    var selectedClusterIds: Set<String> = []
    var selectedResourceType: ResourceType = .pods
    var selectedCRD: CRDDefinition? = nil
    var selectedNamespace: String? = nil
    var availableNamespaces: [String: [String]] = [:]
    var searchText: String = ""

    // CRD support
    var discoveredCRDs: [CRDDefinition] = []
    var customResources: [String: [GenericK8sResource]] = [:]  // keyed by clusterId

    // Convenience proxies to shared store
    var availableConnections: [ClusterConnection] { store.availableConnections }
    var kubeConfigPaths: [String] {
        get { store.kubeConfigPaths }
        set { store.kubeConfigPaths = newValue }
    }
    var kubeConfigDirs: [String] {
        get { store.kubeConfigDirs }
        set { store.kubeConfigDirs = newValue }
    }

    // Resource data (per window — each window can look at different resources)
    var pods: [String: [Pod]] = [:]
    var deployments: [String: [Deployment]] = [:]
    var services: [String: [Service]] = [:]
    var nodes: [String: [Node]] = [:]
    var statefulSets: [String: [StatefulSet]] = [:]
    var daemonSets: [String: [DaemonSet]] = [:]
    var replicaSets: [String: [ReplicaSet]] = [:]
    var jobs: [String: [Job]] = [:]
    var cronJobs: [String: [CronJob]] = [:]
    var configMaps: [String: [ConfigMap]] = [:]
    var secrets: [String: [Secret]] = [:]
    var ingresses: [String: [Ingress]] = [:]
    var ingressClasses: [String: [IngressClass]] = [:]
    var persistentVolumes: [String: [PersistentVolume]] = [:]
    var persistentVolumeClaims: [String: [PersistentVolumeClaim]] = [:]
    var networkPolicies: [String: [NetworkPolicy]] = [:]
    var serviceAccounts: [String: [ServiceAccount]] = [:]
    var horizontalPodAutoscalers: [String: [HorizontalPodAutoscaler]] = [:]
    var namespaces: [String: [Namespace]] = [:]
    var endpoints: [String: [Endpoints]] = [:]

    // Cluster overview
    var showClusterOverview: Bool = false
    var podMetricsCache: [String: [PodMetrics]] = [:]  // keyed by clusterId
    var nodeMetricsCache: [String: [NodeMetrics]] = [:]
    var metricsAvailable: [String: Bool] = [:]  // keyed by clusterId

    var isLoading: Bool = false
    var errorMessage: String?
    var lastRefreshTime: Date?

    private var refreshTask: Task<Void, Never>?
    private var watchTask: Task<Void, Never>?
    private var resourceVersions: [String: String] = [:]  // clusterId -> resourceVersion

    init(id: String = UUID().uuidString) {
        self.id = id
    }

    var activeConnections: [ClusterConnection] {
        store.availableConnections.filter { selectedClusterIds.contains($0.id) }
    }

    // MARK: - Cluster Discovery (delegates to store)

    func discoverClusters() async {
        await store.discoverClusters()
    }

    func addKubeConfigPaths(_ paths: [String]) { store.addKubeConfigPaths(paths) }
    func addKubeConfigDirectory(_ dir: String) { store.addKubeConfigDirectory(dir) }
    func removeKubeConfigPath(_ path: String) { store.removeKubeConfigPath(path) }
    func removeKubeConfigDirectory(_ dir: String) { store.removeKubeConfigDirectory(dir) }

    // MARK: - Connection

    func connect(to connection: ClusterConnection) async {
        let client = K8sAPIClient(connection: connection)
        await MainActor.run {
            activeClients[connection.id] = client
            connectionStatuses[connection.id] = .connecting
        }

        do {
            let version = try await client.getServerVersion()
            let namespaces = try await client.listNamespaces()
            await MainActor.run {
                connectionStatuses[connection.id] = .connected(serverVersion: version)
                availableNamespaces[connection.id] = namespaces
                if selectedNamespace == nil, let defaultNs = connection.defaultNamespace {
                    selectedNamespace = defaultNs
                } else if selectedNamespace == nil {
                    selectedNamespace = "default"
                }
            }
            // Discover CRDs
            if let crds = try? await client.discoverCRDs() {
                await MainActor.run { discoveredCRDs = crds }
            }

            await loadResources(for: connection.id)
        } catch {
            await MainActor.run {
                connectionStatuses[connection.id] = .error(error.localizedDescription)
            }
        }
    }

    func disconnect(from connectionId: String) {
        activeClients.removeValue(forKey: connectionId)
        connectionStatuses[connectionId] = .disconnected
        selectedClusterIds.remove(connectionId)
        clearResources(for: connectionId)
    }

    func toggleCluster(_ connection: ClusterConnection) async {
        if selectedClusterIds.contains(connection.id) {
            disconnect(from: connection.id)
        } else {
            selectedClusterIds.insert(connection.id)
            await connect(to: connection)
        }
    }

    func disconnectAll() {
        stopWatch()
        for id in selectedClusterIds {
            activeClients.removeValue(forKey: id)
            connectionStatuses[id] = .disconnected
            clearResources(for: id)
        }
        selectedClusterIds.removeAll()
        showMainWindow = false
        stopAutoRefresh()
    }

    // MARK: - Resources

    func refresh() async {
        for id in selectedClusterIds {
            if let crd = selectedCRD {
                await loadCustomResources(crd: crd, for: id)
            } else {
                await loadResources(for: id)
            }
        }
    }

    func loadCustomResources(crd: CRDDefinition, for clusterId: String) async {
        guard let client = activeClients[clusterId] else { return }
        await MainActor.run { isLoading = true }
        do {
            let items = try await client.listCustomResources(crd: crd, namespace: crd.isNamespaced ? selectedNamespace : nil)
            let resources = items.map { GenericK8sResource(raw: $0, crd: crd) }
            await MainActor.run { customResources[clusterId] = resources }
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
        await MainActor.run { isLoading = false; lastRefreshTime = Date() }
    }

    func selectCRD(_ crd: CRDDefinition) {
        selectedCRD = crd
        showClusterOverview = false
        Task { await refresh() }
    }

    func selectBuiltInType(_ type: ResourceType) {
        selectedCRD = nil
        showClusterOverview = false
        selectedResourceType = type
    }

    func loadResources(for clusterId: String) async {
        guard let client = activeClients[clusterId] else { return }
        stopWatch()
        await MainActor.run { isLoading = true }

        do {
            let ns = selectedNamespace
            switch selectedResourceType {
            case .pods:
                let r = try await client.listWithVersion(Pod.self, resourceType: .pods, namespace: ns)
                await MainActor.run { pods[clusterId] = r.items; resourceVersions[clusterId] = r.resourceVersion }
            case .deployments:
                let r = try await client.listWithVersion(Deployment.self, resourceType: .deployments, namespace: ns)
                await MainActor.run { deployments[clusterId] = r.items; resourceVersions[clusterId] = r.resourceVersion }
            case .services:
                let r = try await client.listWithVersion(Service.self, resourceType: .services, namespace: ns)
                await MainActor.run { services[clusterId] = r.items; resourceVersions[clusterId] = r.resourceVersion }
            case .nodes:
                let r = try await client.listWithVersion(Node.self, resourceType: .nodes)
                await MainActor.run { nodes[clusterId] = r.items; resourceVersions[clusterId] = r.resourceVersion }
            case .statefulSets:
                let r = try await client.listWithVersion(StatefulSet.self, resourceType: .statefulSets, namespace: ns)
                await MainActor.run { statefulSets[clusterId] = r.items; resourceVersions[clusterId] = r.resourceVersion }
            case .daemonSets:
                let r = try await client.listWithVersion(DaemonSet.self, resourceType: .daemonSets, namespace: ns)
                await MainActor.run { daemonSets[clusterId] = r.items; resourceVersions[clusterId] = r.resourceVersion }
            case .replicaSets:
                let r = try await client.listWithVersion(ReplicaSet.self, resourceType: .replicaSets, namespace: ns)
                await MainActor.run { replicaSets[clusterId] = r.items; resourceVersions[clusterId] = r.resourceVersion }
            case .jobs:
                let r = try await client.listWithVersion(Job.self, resourceType: .jobs, namespace: ns)
                await MainActor.run { jobs[clusterId] = r.items; resourceVersions[clusterId] = r.resourceVersion }
            case .cronJobs:
                let r = try await client.listWithVersion(CronJob.self, resourceType: .cronJobs, namespace: ns)
                await MainActor.run { cronJobs[clusterId] = r.items; resourceVersions[clusterId] = r.resourceVersion }
            case .configMaps:
                let r = try await client.listWithVersion(ConfigMap.self, resourceType: .configMaps, namespace: ns)
                await MainActor.run { configMaps[clusterId] = r.items; resourceVersions[clusterId] = r.resourceVersion }
            case .secrets:
                let r = try await client.listWithVersion(Secret.self, resourceType: .secrets, namespace: ns)
                await MainActor.run { secrets[clusterId] = r.items; resourceVersions[clusterId] = r.resourceVersion }
            case .ingresses:
                let r = try await client.listWithVersion(Ingress.self, resourceType: .ingresses, namespace: ns)
                await MainActor.run { ingresses[clusterId] = r.items; resourceVersions[clusterId] = r.resourceVersion }
            case .ingressClasses:
                let r = try await client.listWithVersion(IngressClass.self, resourceType: .ingressClasses)
                await MainActor.run { ingressClasses[clusterId] = r.items; resourceVersions[clusterId] = r.resourceVersion }
            case .persistentVolumes:
                let r = try await client.listWithVersion(PersistentVolume.self, resourceType: .persistentVolumes)
                await MainActor.run { persistentVolumes[clusterId] = r.items; resourceVersions[clusterId] = r.resourceVersion }
            case .persistentVolumeClaims:
                let r = try await client.listWithVersion(PersistentVolumeClaim.self, resourceType: .persistentVolumeClaims, namespace: ns)
                await MainActor.run { persistentVolumeClaims[clusterId] = r.items; resourceVersions[clusterId] = r.resourceVersion }
            case .networkPolicies:
                let r = try await client.listWithVersion(NetworkPolicy.self, resourceType: .networkPolicies, namespace: ns)
                await MainActor.run { networkPolicies[clusterId] = r.items; resourceVersions[clusterId] = r.resourceVersion }
            case .serviceAccounts:
                let r = try await client.listWithVersion(ServiceAccount.self, resourceType: .serviceAccounts, namespace: ns)
                await MainActor.run { serviceAccounts[clusterId] = r.items; resourceVersions[clusterId] = r.resourceVersion }
            case .horizontalPodAutoscalers:
                let r = try await client.listWithVersion(HorizontalPodAutoscaler.self, resourceType: .horizontalPodAutoscalers, namespace: ns)
                await MainActor.run { horizontalPodAutoscalers[clusterId] = r.items; resourceVersions[clusterId] = r.resourceVersion }
            case .namespaces:
                let r = try await client.listWithVersion(Namespace.self, resourceType: .namespaces)
                await MainActor.run { namespaces[clusterId] = r.items; resourceVersions[clusterId] = r.resourceVersion }
            case .endpoints:
                let r = try await client.listWithVersion(Endpoints.self, resourceType: .endpoints, namespace: ns)
                await MainActor.run { endpoints[clusterId] = r.items; resourceVersions[clusterId] = r.resourceVersion }
            }
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }

        await MainActor.run { isLoading = false; lastRefreshTime = Date() }

        // Fetch metrics for resource types that display them
        if [.pods, .nodes].contains(selectedResourceType) {
            await fetchMetrics(for: clusterId)
        }

        // Start watching for live updates on core resource types
        startWatch(for: clusterId)
    }

    // MARK: - Metrics

    func fetchMetrics(for clusterId: String) async {
        guard let client = activeClients[clusterId] else { return }
        do {
            async let podMetrics = client.listPodMetrics(namespace: selectedNamespace)
            async let nodeMetrics = client.listNodeMetrics()
            let (pods, nodes) = try await (podMetrics, nodeMetrics)
            await MainActor.run {
                podMetricsCache[clusterId] = pods
                nodeMetricsCache[clusterId] = nodes
                metricsAvailable[clusterId] = true
            }
        } catch {
            await MainActor.run {
                metricsAvailable[clusterId] = false
            }
        }
    }

    func fetchAllMetrics() async {
        for clusterId in selectedClusterIds {
            await fetchMetrics(for: clusterId)
        }
    }

    func startAutoRefresh(interval: TimeInterval = 30) {
        refreshTask?.cancel()
        refreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                // Only do full refresh if watch isn't active (fallback for unsupported types)
                if watchTask == nil {
                    await refresh()
                }
            }
        }
    }

    func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    // MARK: - Watch API

    func startWatch(for clusterId: String) {
        watchTask?.cancel()
        watchTask = nil
        guard let client = activeClients[clusterId] else { return }
        let type = selectedResourceType
        let ns = type.isNamespaced ? selectedNamespace : nil

        watchTask = Task.detached { [weak self] in
            guard let self = self else { return }
            var failCount = 0
            while !Task.isCancelled && failCount < 5 {
                do {
                    failCount = 0  // Reset on successful connection
                    try await self.runWatch(client: client, resourceType: type, namespace: ns, clusterId: clusterId)
                } catch is CancellationError {
                    break
                } catch K8sError.watchGone {
                    break
                } catch {
                    guard !Task.isCancelled else { break }
                    failCount += 1
                    // Exponential backoff: 3s, 9s, 27s, 81s, then give up
                    let delay = min(3.0 * pow(3.0, Double(failCount - 1)), 120.0)
                    try? await Task.sleep(for: .seconds(delay))
                }
            }
            // Watch gave up — auto-refresh will handle updates
        }
    }

    private func runWatch(client: K8sAPIClient, resourceType: ResourceType, namespace: String?, clusterId: String) async throws {
        guard let rv = resourceVersions[clusterId] else { return }

        // Use a type-erased approach — switch on resource type and run typed watch
        switch resourceType {
        case .pods: try await typedWatch(Pod.self, client: client, rt: resourceType, ns: namespace, cid: clusterId, rv: rv, kp: \.pods)
        case .deployments: try await typedWatch(Deployment.self, client: client, rt: resourceType, ns: namespace, cid: clusterId, rv: rv, kp: \.deployments)
        case .services: try await typedWatch(Service.self, client: client, rt: resourceType, ns: namespace, cid: clusterId, rv: rv, kp: \.services)
        case .nodes: try await typedWatch(Node.self, client: client, rt: resourceType, ns: nil, cid: clusterId, rv: rv, kp: \.nodes)
        case .statefulSets: try await typedWatch(StatefulSet.self, client: client, rt: resourceType, ns: namespace, cid: clusterId, rv: rv, kp: \.statefulSets)
        case .daemonSets: try await typedWatch(DaemonSet.self, client: client, rt: resourceType, ns: namespace, cid: clusterId, rv: rv, kp: \.daemonSets)
        case .replicaSets: try await typedWatch(ReplicaSet.self, client: client, rt: resourceType, ns: namespace, cid: clusterId, rv: rv, kp: \.replicaSets)
        case .jobs: try await typedWatch(Job.self, client: client, rt: resourceType, ns: namespace, cid: clusterId, rv: rv, kp: \.jobs)
        case .cronJobs: try await typedWatch(CronJob.self, client: client, rt: resourceType, ns: namespace, cid: clusterId, rv: rv, kp: \.cronJobs)
        case .configMaps: try await typedWatch(ConfigMap.self, client: client, rt: resourceType, ns: namespace, cid: clusterId, rv: rv, kp: \.configMaps)
        case .secrets: try await typedWatch(Secret.self, client: client, rt: resourceType, ns: namespace, cid: clusterId, rv: rv, kp: \.secrets)
        default:
            // For other types, just wait (auto-refresh handles them)
            try await Task.sleep(for: .seconds(30))
        }
    }

    private func typedWatch<T: K8sResource>(
        _ type: T.Type,
        client: K8sAPIClient,
        rt: ResourceType,
        ns: String?,
        cid: String,
        rv: String,
        kp: ReferenceWritableKeyPath<AppViewModel, [String: [T]]>
    ) async throws {
        let stream = client.watch(type, resourceType: rt, namespace: ns, resourceVersion: rv)
        for try await event in stream {
            await MainActor.run {
                var items = self[keyPath: kp][cid] ?? []
                switch event.type {
                case .ADDED:
                    if !items.contains(where: { $0.id == event.object.id }) {
                        items.append(event.object)
                    }
                case .MODIFIED:
                    if let idx = items.firstIndex(where: { $0.id == event.object.id }) {
                        items[idx] = event.object
                    } else {
                        items.append(event.object)
                    }
                case .DELETED:
                    items.removeAll { $0.id == event.object.id }
                case .BOOKMARK:
                    // Update resourceVersion only
                    if let rv = event.object.metadata.resourceVersion {
                        self.resourceVersions[cid] = rv
                    }
                case .ERROR:
                    break
                }
                self[keyPath: kp][cid] = items
                // Update resourceVersion from the event object
                if let rv = event.object.metadata.resourceVersion {
                    self.resourceVersions[cid] = rv
                }
            }
        }
    }

    func stopWatch() {
        watchTask?.cancel()
        watchTask = nil
        resourceVersions.removeAll()
    }

    // MARK: - State Persistence (keyed by cluster IDs for stable recall)

    /// Stable key based on connected cluster IDs — same clusters = same saved state
    private var stateKey: String {
        let sortedIds = selectedClusterIds.sorted().joined(separator: "+")
        return "clusterState.\(sortedIds)"
    }

    func saveState() {
        guard !selectedClusterIds.isEmpty else { return }
        let state = WindowState(
            namespace: selectedNamespace,
            resourceType: selectedResourceType.rawValue,
            clusterIds: Array(selectedClusterIds)
        )
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: stateKey)
        }
    }

    func restoreState() {
        guard !selectedClusterIds.isEmpty else { return }
        guard let data = UserDefaults.standard.data(forKey: stateKey),
              let state = try? JSONDecoder().decode(WindowState.self, from: data) else { return }

        if let ns = state.namespace {
            selectedNamespace = ns
        }
        if let rt = ResourceType(rawValue: state.resourceType) {
            selectedResourceType = rt
        }
    }

    private func clearResources(for clusterId: String) {
        pods.removeValue(forKey: clusterId)
        deployments.removeValue(forKey: clusterId)
        services.removeValue(forKey: clusterId)
        nodes.removeValue(forKey: clusterId)
        statefulSets.removeValue(forKey: clusterId)
        daemonSets.removeValue(forKey: clusterId)
        replicaSets.removeValue(forKey: clusterId)
        jobs.removeValue(forKey: clusterId)
        cronJobs.removeValue(forKey: clusterId)
        configMaps.removeValue(forKey: clusterId)
        secrets.removeValue(forKey: clusterId)
        ingresses.removeValue(forKey: clusterId)
        ingressClasses.removeValue(forKey: clusterId)
        persistentVolumes.removeValue(forKey: clusterId)
        persistentVolumeClaims.removeValue(forKey: clusterId)
        networkPolicies.removeValue(forKey: clusterId)
        serviceAccounts.removeValue(forKey: clusterId)
        horizontalPodAutoscalers.removeValue(forKey: clusterId)
        namespaces.removeValue(forKey: clusterId)
        endpoints.removeValue(forKey: clusterId)
        customResources.removeValue(forKey: clusterId)
        podMetricsCache.removeValue(forKey: clusterId)
        nodeMetricsCache.removeValue(forKey: clusterId)
        metricsAvailable.removeValue(forKey: clusterId)
    }
}

// MARK: - Persisted Window State

struct WindowState: Codable {
    var namespace: String?
    var resourceType: String
    var clusterIds: [String]
}
