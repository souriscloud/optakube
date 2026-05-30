import Foundation

// MARK: - Resource Loading & Metrics
//
// The list side of the resource lifecycle: the big per-type `loadResources` switch,
// custom-resource (CRD) loading, metrics fetch, and the per-cluster cache teardown.
// The live-update (watch) side lives in `AppViewModel+Watch.swift`.

extension AppViewModel {
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
        showHelmReleases = false
        Task { await refresh() }
    }

    func selectBuiltInType(_ type: ResourceType) {
        selectedCRD = nil
        showClusterOverview = false
        showHelmReleases = false
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
                await MainActor.run {
                    pods[clusterId] = r.items
                    resourceVersions[clusterId] = r.resourceVersion
                    NotificationsService.shared.observe(pods: r.items, clusterId: clusterId)
                }
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
            case .roles:
                let r = try await client.listWithVersion(Role.self, resourceType: .roles, namespace: ns)
                await MainActor.run { roles[clusterId] = r.items; resourceVersions[clusterId] = r.resourceVersion }
            case .roleBindings:
                let r = try await client.listWithVersion(RoleBinding.self, resourceType: .roleBindings, namespace: ns)
                await MainActor.run { roleBindings[clusterId] = r.items; resourceVersions[clusterId] = r.resourceVersion }
            case .clusterRoles:
                let r = try await client.listWithVersion(ClusterRole.self, resourceType: .clusterRoles)
                await MainActor.run { clusterRoles[clusterId] = r.items; resourceVersions[clusterId] = r.resourceVersion }
            case .clusterRoleBindings:
                let r = try await client.listWithVersion(ClusterRoleBinding.self, resourceType: .clusterRoleBindings)
                await MainActor.run { clusterRoleBindings[clusterId] = r.items; resourceVersions[clusterId] = r.resourceVersion }
            case .storageClasses:
                let r = try await client.listWithVersion(StorageClass.self, resourceType: .storageClasses)
                await MainActor.run { storageClasses[clusterId] = r.items; resourceVersions[clusterId] = r.resourceVersion }
            case .resourceQuotas:
                let r = try await client.listWithVersion(ResourceQuota.self, resourceType: .resourceQuotas, namespace: ns)
                await MainActor.run { resourceQuotas[clusterId] = r.items; resourceVersions[clusterId] = r.resourceVersion }
            case .podDisruptionBudgets:
                let r = try await client.listWithVersion(PodDisruptionBudget.self, resourceType: .podDisruptionBudgets, namespace: ns)
                await MainActor.run { podDisruptionBudgets[clusterId] = r.items; resourceVersions[clusterId] = r.resourceVersion }
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

    // MARK: - Cache teardown

    func clearResources(for clusterId: String) {
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
        roles.removeValue(forKey: clusterId)
        roleBindings.removeValue(forKey: clusterId)
        clusterRoles.removeValue(forKey: clusterId)
        clusterRoleBindings.removeValue(forKey: clusterId)
        storageClasses.removeValue(forKey: clusterId)
        resourceQuotas.removeValue(forKey: clusterId)
        podDisruptionBudgets.removeValue(forKey: clusterId)
        helmReleases.removeValue(forKey: clusterId)
        customResources.removeValue(forKey: clusterId)
        podMetricsCache.removeValue(forKey: clusterId)
        nodeMetricsCache.removeValue(forKey: clusterId)
        metricsAvailable.removeValue(forKey: clusterId)
    }
}
