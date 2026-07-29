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
    /// Kubernetes label selector typed into the list filter (e.g. `app=web,tier!=db`).
    /// Ephemeral per window — narrows the visible rows on top of `searchText`.
    var labelFilter: String = ""

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
    var roles: [String: [Role]] = [:]
    var roleBindings: [String: [RoleBinding]] = [:]
    var clusterRoles: [String: [ClusterRole]] = [:]
    var clusterRoleBindings: [String: [ClusterRoleBinding]] = [:]
    var storageClasses: [String: [StorageClass]] = [:]
    var resourceQuotas: [String: [ResourceQuota]] = [:]
    var podDisruptionBudgets: [String: [PodDisruptionBudget]] = [:]
    var limitRanges: [String: [LimitRange]] = [:]
    var priorityClasses: [String: [PriorityClass]] = [:]
    var leases: [String: [Lease]] = [:]
    var mutatingWebhookConfigurations: [String: [MutatingWebhookConfiguration]] = [:]
    var validatingWebhookConfigurations: [String: [ValidatingWebhookConfiguration]] = [:]

    // Helm releases (all stored revisions, per cluster)
    var showHelmReleases: Bool = false
    var helmReleases: [String: [HelmRelease]] = [:]

    // Cluster-wide events browser
    var showClusterEvents: Bool = false
    var clusterEvents: [String: [K8sEvent]] = [:]

    // Cluster overview
    var showClusterOverview: Bool = false
    var podMetricsCache: [String: [PodMetrics]] = [:]  // keyed by clusterId
    var nodeMetricsCache: [String: [NodeMetrics]] = [:]
    var metricsAvailable: [String: Bool] = [:]  // keyed by clusterId

    var isLoading: Bool = false
    var errorMessage: String?
    var lastRefreshTime: Date?

    // Note: these are `internal` (not `private`) because the watch/resources logic
    // lives in `AppViewModel+Watch.swift` / `AppViewModel+Resources.swift`. Stored
    // properties can't live in extensions, and `private` is file-scoped, so cross-file
    // extensions need at least internal access.
    var refreshTask: Task<Void, Never>?
    /// One watch task per cluster. Was previously a single `watchTask` which meant
    /// only the most-recently-loaded cluster got live updates — every prior cluster's
    /// watch was silently cancelled. Now each cluster runs its own.
    var watchTasks: [String: Task<Void, Never>] = [:]
    var resourceVersions: [String: String] = [:]  // clusterId -> resourceVersion

    init(id: String = UUID().uuidString) {
        self.id = id
    }

    var activeConnections: [ClusterConnection] {
        store.availableConnections.filter { selectedClusterIds.contains($0.id) }
    }

    // MARK: - Helm

    /// Switch the content area to the Helm releases browser and load them.
    @MainActor
    func showHelm() {
        selectedCRD = nil
        showClusterOverview = false
        showClusterEvents = false
        showHelmReleases = true
        Task { await loadHelmReleases() }
    }

    /// Switch the content area to the cluster-wide events browser and load them.
    @MainActor
    func showEvents() {
        selectedCRD = nil
        showClusterOverview = false
        showHelmReleases = false
        showClusterEvents = true
        Task { await loadClusterEvents() }
    }

    @MainActor
    func loadClusterEvents() async {
        isLoading = true
        for clusterId in selectedClusterIds {
            guard let client = activeClients[clusterId] else { continue }
            do {
                let events = try await client.listEvents(namespace: selectedNamespace)
                clusterEvents[clusterId] = events
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        isLoading = false
        lastRefreshTime = Date()
    }

    @MainActor
    func loadHelmReleases() async {
        isLoading = true
        for clusterId in selectedClusterIds {
            guard let client = activeClients[clusterId] else { continue }
            do {
                let releases = try await client.listHelmReleases(namespace: selectedNamespace)
                helmReleases[clusterId] = releases
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        isLoading = false
        lastRefreshTime = Date()
    }

    // MARK: - Saved Views

    /// Jump to a pinned view: set namespace, resource type, and label filter, then
    /// refresh. Leaves CRD/overview modes and reuses the existing connection.
    @MainActor
    func applySavedView(_ view: SavedView) {
        guard let type = view.resolvedType else { return }
        selectedCRD = nil
        showClusterOverview = false
        showHelmReleases = false
        showClusterEvents = false
        selectedNamespace = view.namespace
        labelFilter = view.labelFilter
        selectedResourceType = type
        Task { await refresh() }
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

            // Listing namespaces is a cluster-scoped read. A namespace-scoped identity —
            // an extremely common setup, where `kubectl -n team-a get pods` works fine —
            // cannot do it, and letting that 403 escape aborted the entire connection,
            // making the app unusable for those users. Fall back to the namespace the
            // kubeconfig context already names.
            let namespaces: [String]
            if let listed = try? await client.listNamespaces(), !listed.isEmpty {
                namespaces = listed
            } else {
                namespaces = [connection.defaultNamespace ?? "default"]
            }

            await MainActor.run {
                connectionStatuses[connection.id] = .connected(serverVersion: version)
                availableNamespaces[connection.id] = namespaces
                if selectedNamespace == nil, let defaultNs = connection.defaultNamespace {
                    selectedNamespace = defaultNs
                } else if selectedNamespace == nil {
                    // Prefer something we know exists over a hardcoded "default", which
                    // may not exist or may not be readable.
                    selectedNamespace = namespaces.contains("default") ? "default" : namespaces.first
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
        stopWatch(for: connectionId)
        activeClients.removeValue(forKey: connectionId)
        connectionStatuses[connectionId] = .disconnected
        selectedClusterIds.remove(connectionId)
        clearResources(for: connectionId)
        Task { @MainActor in NotificationsService.shared.reset(clusterId: connectionId) }
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

}
