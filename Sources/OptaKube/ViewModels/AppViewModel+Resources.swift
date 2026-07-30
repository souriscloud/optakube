import Foundation

// MARK: - Resource Loading & Metrics
//
// The list side of the resource lifecycle: the big per-type `loadResources` switch,
// custom-resource (CRD) loading, metrics fetch, and the per-cluster cache teardown.
// The live-update (watch) side lives in `AppViewModel+Watch.swift`.

extension AppViewModel {
    func refresh() async {
        // ⌘R and the toolbar Refresh button both land here, and it used to only ever
        // reload resource lists — so in the Helm and Events browsers Refresh silently did
        // nothing, and neither view had auto-refresh either. Both were frozen once loaded.
        if showHelmReleases {
            await loadHelmReleases()
            return
        }
        if showClusterEvents {
            await loadClusterEvents()
            return
        }
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
            await MainActor.run {
                customResources[clusterId] = resources
                resourceLoadErrors.removeValue(forKey: clusterId)
                errorMessage = nil
            }
        } catch {
            let message = error.localizedDescription
            await MainActor.run {
                errorMessage = message
                resourceLoadErrors[clusterId] = message
            }
        }
        await MainActor.run { isLoading = false; lastRefreshTime = Date() }
    }

    func selectCRD(_ crd: CRDDefinition) {
        selectedCRD = crd
        showClusterOverview = false
        showHelmReleases = false
        showClusterEvents = false
        Task { await refresh() }
    }

    func selectBuiltInType(_ type: ResourceType) {
        selectedCRD = nil
        showClusterOverview = false
        showHelmReleases = false
        showClusterEvents = false
        selectedResourceType = type
    }

    func loadResources(for clusterId: String) async {
        guard activeClients[clusterId] != nil else { return }
        // Only this cluster's watch. `stopWatch()` cancelled *every* cluster's watch and
        // cleared all resourceVersions, so `refresh()` looping over clusters serially left
        // only the last one with live updates — reintroducing the single-watch bug the
        // per-cluster watchTasks dictionary exists to fix.
        stopWatch(for: clusterId)
        await MainActor.run { isLoading = true }

        await fetchList(for: clusterId)

        await MainActor.run { isLoading = false; lastRefreshTime = Date() }

        // Fetch metrics for resource types that display them
        if [.pods, .nodes].contains(selectedResourceType) {
            await fetchMetrics(for: clusterId)
        }

        // Start watching for live updates
        startWatch(for: clusterId)
    }

    /// Re-lists without touching the watch registration.
    ///
    /// Used by the watch loop when the API server reports the resourceVersion has expired:
    /// it needs a fresh list and a usable resourceVersion, but must not cancel or restart
    /// the very task it is running on — which is what calling `loadResources` would do.
    func relistForWatchRestart(for clusterId: String) async {
        await fetchList(for: clusterId)
        await MainActor.run { lastRefreshTime = Date() }
    }

    private func fetchList(for clusterId: String) async {
        guard let client = activeClients[clusterId] else { return }

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
            case .limitRanges:
                let r = try await client.listWithVersion(LimitRange.self, resourceType: .limitRanges, namespace: ns)
                await MainActor.run { limitRanges[clusterId] = r.items; resourceVersions[clusterId] = r.resourceVersion }
            case .priorityClasses:
                let r = try await client.listWithVersion(PriorityClass.self, resourceType: .priorityClasses)
                await MainActor.run { priorityClasses[clusterId] = r.items; resourceVersions[clusterId] = r.resourceVersion }
            case .leases:
                let r = try await client.listWithVersion(Lease.self, resourceType: .leases, namespace: ns)
                await MainActor.run { leases[clusterId] = r.items; resourceVersions[clusterId] = r.resourceVersion }
            case .mutatingWebhookConfigurations:
                let r = try await client.listWithVersion(MutatingWebhookConfiguration.self, resourceType: .mutatingWebhookConfigurations)
                await MainActor.run { mutatingWebhookConfigurations[clusterId] = r.items; resourceVersions[clusterId] = r.resourceVersion }
            case .validatingWebhookConfigurations:
                let r = try await client.listWithVersion(ValidatingWebhookConfiguration.self, resourceType: .validatingWebhookConfigurations)
                await MainActor.run { validatingWebhookConfigurations[clusterId] = r.items; resourceVersions[clusterId] = r.resourceVersion }
            }
            // Clear on success. `errorMessage` was never set back to nil anywhere, so a
            // single transient failure pinned a truncated error to the status bar for the
            // window's entire lifetime, sitting next to perfectly healthy data.
            await MainActor.run {
                resourceLoadErrors.removeValue(forKey: clusterId)
                errorMessage = nil
            }
        } catch {
            let message = error.localizedDescription
            await MainActor.run {
                errorMessage = message
                resourceLoadErrors[clusterId] = message
            }
        }
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
        limitRanges.removeValue(forKey: clusterId)
        priorityClasses.removeValue(forKey: clusterId)
        leases.removeValue(forKey: clusterId)
        mutatingWebhookConfigurations.removeValue(forKey: clusterId)
        validatingWebhookConfigurations.removeValue(forKey: clusterId)
        helmReleases.removeValue(forKey: clusterId)
        clusterEvents.removeValue(forKey: clusterId)
        customResources.removeValue(forKey: clusterId)
        podMetricsCache.removeValue(forKey: clusterId)
        nodeMetricsCache.removeValue(forKey: clusterId)
        metricsAvailable.removeValue(forKey: clusterId)
    }
}
