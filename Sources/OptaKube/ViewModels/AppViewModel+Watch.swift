import Foundation

// MARK: - Live Updates: Watch Engine & Auto-Refresh
//
// The push side of the resource lifecycle. One watch task per cluster streams
// ADDED/MODIFIED/DELETED events and applies them to the resource cache; bursts are
// coalesced (see `WatchCoalescer`) so a startup storm is one re-render per ~100ms
// window rather than one per event.
//
// The loop is designed around the fact that watches *always* end: the API server closes
// them routinely (every few minutes), a laptop sleep leaves a half-open socket, and a
// resourceVersion goes stale after etcd compaction. Ending is normal, so every exit path
// either reconnects or reports itself as stale — it must never just stop quietly, which
// is what used to freeze a window's data behind a healthy-looking UI.

// Every function here that touches `watchTasks`, `resourceVersions` or `watchHealth` is
// `@MainActor`. They were reachable from three different execution contexts — the
// auto-refresh Task, `loadResources` (nonisolated, and awaited from a plain `Task` in the
// welcome window), and `applyWatchBatch` on the main actor — so two threads could mutate
// the same Swift Dictionary at once. That is undefined behaviour: the observed symptoms
// would be an occasional "index out of range" or malloc crash, or a watch that silently
// vanished. The network and decode paths are deliberately left off the main actor so a
// 10,000-pod list still doesn't hitch the UI.
extension AppViewModel {
    @MainActor
    func startAutoRefresh(interval: TimeInterval = 30) {
        refreshTask?.cancel()
        refreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                // Poll any selected cluster that isn't currently being fed by a live
                // watch. This keys off watch *health*, not off the presence of an entry in
                // `watchTasks`: a finished task used to stay registered forever, so this
                // set was always empty and the fallback never ran even when the watch had
                // given up completely.
                let needsPoll = selectedClusterIds.filter { id in
                    switch watchHealth[id] {
                    case .live: return false
                    case .reconnecting, .stale, nil: return true
                    }
                }
                if !needsPoll.isEmpty {
                    await refresh()
                }
            }
        }
    }

    @MainActor
    func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    @MainActor
    func startWatch(for clusterId: String) {
        watchTasks[clusterId]?.cancel()
        watchTasks[clusterId] = nil
        guard let client = activeClients[clusterId] else { return }
        let type = selectedResourceType
        let ns = type.isNamespaced ? selectedNamespace : nil

        let task = Task.detached { [weak self] in
            guard let self = self else { return }
            var failCount = 0

            while !Task.isCancelled {
                do {
                    await self.setWatchHealth(.live, for: clusterId)
                    try await self.runWatch(client: client, resourceType: type,
                                            namespace: ns, clusterId: clusterId)
                    // A clean return means the server closed the stream, which it does as
                    // a matter of course. Reconnect from where we left off.
                    failCount = 0
                } catch is CancellationError {
                    break
                } catch K8sError.watchGone {
                    // The resourceVersion is too old to resume from (etcd compaction, or
                    // simply a long sleep). Re-list for a fresh one and carry on. This
                    // used to `break`, which stopped live updates for good.
                    guard !Task.isCancelled else { break }
                    await self.setWatchHealth(.reconnecting(attempt: 0), for: clusterId)
                    await self.relistForWatchRestart(for: clusterId)
                    failCount = 0
                } catch {
                    guard !Task.isCancelled else { break }
                    failCount += 1
                    if failCount >= 5 {
                        // Hand over to the polling fallback rather than hammering the API
                        // server, and say so in the UI.
                        await self.setWatchHealth(
                            .stale(reason: error.localizedDescription), for: clusterId)
                        break
                    }
                    await self.setWatchHealth(.reconnecting(attempt: failCount), for: clusterId)
                    // 3s, 9s, 27s, 81s
                    let delay = min(3.0 * pow(3.0, Double(failCount - 1)), 120.0)
                    try? await Task.sleep(for: .seconds(delay))
                }
            }

            // Deregister however this task ended, so the polling fallback can take over.
            await self.watchDidExit(clusterId, cancelled: Task.isCancelled)
        }
        watchTasks[clusterId] = task
    }

    @MainActor
    func setWatchHealth(_ health: WatchHealth, for clusterId: String) {
        watchHealth[clusterId] = health
    }

    @MainActor
    private func watchDidExit(_ clusterId: String, cancelled: Bool) {
        watchTasks.removeValue(forKey: clusterId)
        if cancelled {
            // Deliberate teardown (namespace switch, disconnect) — not a health problem.
            watchHealth.removeValue(forKey: clusterId)
        } else if case .live = watchHealth[clusterId] {
            watchHealth[clusterId] = .stale(reason: "The update stream ended.")
        }
    }

    nonisolated private func runWatch(client: K8sAPIClient, resourceType: ResourceType,
                          namespace: String?, clusterId: String) async throws {
        guard let rv = await currentResourceVersion(for: clusterId) else {
            // No resourceVersion means the list hasn't succeeded yet (or was forbidden).
            // Returning immediately let the enclosing `while` spin with no suspension —
            // a pegged CPU core with nothing on screen to explain it. Wait, then retry.
            try await Task.sleep(for: .seconds(10))
            return
        }

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

        // Everything below used to fall into a `default:` branch that slept 30s in a loop
        // while keeping its watchTasks entry alive — so these types had neither live
        // updates nor the polling fallback, and never changed until ⌘R was pressed.
        case .ingresses: try await typedWatch(Ingress.self, client: client, rt: resourceType, ns: namespace, cid: clusterId, rv: rv, kp: \.ingresses)
        case .ingressClasses: try await typedWatch(IngressClass.self, client: client, rt: resourceType, ns: nil, cid: clusterId, rv: rv, kp: \.ingressClasses)
        case .persistentVolumes: try await typedWatch(PersistentVolume.self, client: client, rt: resourceType, ns: nil, cid: clusterId, rv: rv, kp: \.persistentVolumes)
        case .persistentVolumeClaims: try await typedWatch(PersistentVolumeClaim.self, client: client, rt: resourceType, ns: namespace, cid: clusterId, rv: rv, kp: \.persistentVolumeClaims)
        case .networkPolicies: try await typedWatch(NetworkPolicy.self, client: client, rt: resourceType, ns: namespace, cid: clusterId, rv: rv, kp: \.networkPolicies)
        case .serviceAccounts: try await typedWatch(ServiceAccount.self, client: client, rt: resourceType, ns: namespace, cid: clusterId, rv: rv, kp: \.serviceAccounts)
        case .horizontalPodAutoscalers: try await typedWatch(HorizontalPodAutoscaler.self, client: client, rt: resourceType, ns: namespace, cid: clusterId, rv: rv, kp: \.horizontalPodAutoscalers)
        case .namespaces: try await typedWatch(Namespace.self, client: client, rt: resourceType, ns: nil, cid: clusterId, rv: rv, kp: \.namespaces)
        case .endpoints: try await typedWatch(Endpoints.self, client: client, rt: resourceType, ns: namespace, cid: clusterId, rv: rv, kp: \.endpoints)
        case .roles: try await typedWatch(Role.self, client: client, rt: resourceType, ns: namespace, cid: clusterId, rv: rv, kp: \.roles)
        case .roleBindings: try await typedWatch(RoleBinding.self, client: client, rt: resourceType, ns: namespace, cid: clusterId, rv: rv, kp: \.roleBindings)
        case .clusterRoles: try await typedWatch(ClusterRole.self, client: client, rt: resourceType, ns: nil, cid: clusterId, rv: rv, kp: \.clusterRoles)
        case .clusterRoleBindings: try await typedWatch(ClusterRoleBinding.self, client: client, rt: resourceType, ns: nil, cid: clusterId, rv: rv, kp: \.clusterRoleBindings)
        case .storageClasses: try await typedWatch(StorageClass.self, client: client, rt: resourceType, ns: nil, cid: clusterId, rv: rv, kp: \.storageClasses)
        case .resourceQuotas: try await typedWatch(ResourceQuota.self, client: client, rt: resourceType, ns: namespace, cid: clusterId, rv: rv, kp: \.resourceQuotas)
        case .podDisruptionBudgets: try await typedWatch(PodDisruptionBudget.self, client: client, rt: resourceType, ns: namespace, cid: clusterId, rv: rv, kp: \.podDisruptionBudgets)
        case .limitRanges: try await typedWatch(LimitRange.self, client: client, rt: resourceType, ns: namespace, cid: clusterId, rv: rv, kp: \.limitRanges)
        case .priorityClasses: try await typedWatch(PriorityClass.self, client: client, rt: resourceType, ns: nil, cid: clusterId, rv: rv, kp: \.priorityClasses)
        case .leases: try await typedWatch(Lease.self, client: client, rt: resourceType, ns: namespace, cid: clusterId, rv: rv, kp: \.leases)
        case .mutatingWebhookConfigurations: try await typedWatch(MutatingWebhookConfiguration.self, client: client, rt: resourceType, ns: nil, cid: clusterId, rv: rv, kp: \.mutatingWebhookConfigurations)
        case .validatingWebhookConfigurations: try await typedWatch(ValidatingWebhookConfiguration.self, client: client, rt: resourceType, ns: nil, cid: clusterId, rv: rv, kp: \.validatingWebhookConfigurations)
        }
    }

    @MainActor
    private func currentResourceVersion(for clusterId: String) -> String? {
        resourceVersions[clusterId]
    }

    nonisolated private func typedWatch<T: K8sResource>(
        _ type: T.Type,
        client: K8sAPIClient,
        rt: ResourceType,
        ns: String?,
        cid: String,
        rv: String,
        kp: ReferenceWritableKeyPath<AppViewModel, [String: [T]]>
    ) async throws {
        let stream = client.watch(type, resourceType: rt, namespace: ns, resourceVersion: rv)

        // Coalesce bursts. During a startup storm (e.g. hundreds of pods flipping
        // Pending→Running within a couple of seconds) the raw watch emits one event
        // per object; applying each individually means one `@Observable` mutation —
        // and one SwiftUI re-render of the whole table — per event. Instead we buffer
        // events in a small actor and apply them in a single batch on a trailing-edge
        // debounce: every event resets a ~100ms window, and when it fires we drain the
        // whole batch into one UI update. Steady-state single events still apply within
        // 100ms; a final drain after the stream ends guarantees nothing is left stale.
        let coalescer = WatchCoalescer<T>()
        var flushTask: Task<Void, Never>?

        // The flush task is unstructured, so cancelling the watch does not cancel it. It
        // therefore has to check for itself before applying: without this, switching
        // namespace from prod to dev could land a batch of *prod* pods into the dev list
        // after the dev list had loaded, complete with working Delete and Exec actions.
        for try await event in stream {
            let shouldSchedule = await coalescer.add(event)
            if shouldSchedule {
                flushTask = Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(100))
                    guard !Task.isCancelled else { return }
                    let batch = await coalescer.drain()
                    if !batch.isEmpty {
                        await self?.applyWatchBatch(batch, cid: cid, kp: kp)
                    }
                }
            }
            if Task.isCancelled {
                flushTask?.cancel()
                throw CancellationError()
            }
        }

        // Stream ended — let the last scheduled flush finish, then drain any stragglers.
        await flushTask?.value
        let tail = await coalescer.drain()
        if !tail.isEmpty {
            await applyWatchBatch(tail, cid: cid, kp: kp)
        }
    }

    /// Apply a coalesced batch of watch events to the resource array for `cid` in a
    /// single `@Observable` mutation. Builds an id→index map so the apply is O(batch +
    /// items) rather than O(batch × items) — and, more importantly, touches the
    /// published array exactly once per batch instead of once per event.
    @MainActor
    private func applyWatchBatch<T: K8sResource>(
        _ batch: [WatchEvent<T>],
        cid: String,
        kp: ReferenceWritableKeyPath<AppViewModel, [String: [T]]>
    ) {
        guard !batch.isEmpty else { return }
        var items = self[keyPath: kp][cid] ?? []
        var indexByID: [String: Int] = [:]
        indexByID.reserveCapacity(items.count)
        for (i, item) in items.enumerated() { indexByID[item.id] = i }

        var latestRV: String? = resourceVersions[cid]
        for event in batch {
            let obj = event.object
            switch event.type {
            case .ADDED, .MODIFIED:
                if let idx = indexByID[obj.id] {
                    items[idx] = obj
                } else {
                    indexByID[obj.id] = items.count
                    items.append(obj)
                }
            case .DELETED:
                if let idx = indexByID[obj.id] {
                    items.remove(at: idx)
                    indexByID.removeValue(forKey: obj.id)
                    // Reindex the shifted tail. Deletes are infrequent relative to
                    // add/modify, so the occasional O(tail) cost is fine.
                    for j in idx..<items.count { indexByID[items[j].id] = j }
                }
            case .BOOKMARK, .ERROR:
                break
            }
            // Only ever move the resourceVersion forward. An out-of-order or empty value
            // could otherwise rewind it and leave the next watch resuming from a version
            // the server has already discarded.
            if let rv = obj.metadata.resourceVersion, Self.resourceVersionIsNewer(rv, than: latestRV) {
                latestRV = rv
            }
        }

        self[keyPath: kp][cid] = items
        if let rv = latestRV { resourceVersions[cid] = rv }

        // Pod-restart notifications were only ever fed from `loadResources`, so they
        // effectively required sitting on the Pods list pressing ⌘R. Feed them from the
        // live stream too, which is where a restart actually shows up first.
        if let pods = items as? [Pod] {
            NotificationsService.shared.observe(pods: pods, clusterId: cid)
        }
        // Live events are a refresh. Without this the status bar showed the last *list*
        // time, so a healthy stream and a frozen one both read "42m ago".
        lastRefreshTime = Date()
    }

    /// resourceVersions are opaque strings, but every real API server uses a monotonically
    /// increasing integer. Compare numerically when both parse, and otherwise accept the
    /// new value rather than risk getting stuck on an old one.
    static func resourceVersionIsNewer(_ candidate: String, than current: String?) -> Bool {
        guard let current, !current.isEmpty else { return true }
        if let a = UInt64(candidate), let b = UInt64(current) { return a > b }
        return true
    }

    /// Tear down and restart every watch, and re-list. Called on wake from sleep and on a
    /// network path change: a socket that was open when the Mac slept is usually
    /// half-open afterwards, which produces neither bytes nor an error.
    @MainActor
    func restartWatches() async {
        for (_, task) in watchTasks { task.cancel() }
        watchTasks.removeAll()
        watchHealth.removeAll()
        await refresh()
    }

    @MainActor
    func stopWatch() {
        for (_, task) in watchTasks { task.cancel() }
        watchTasks.removeAll()
        resourceVersions.removeAll()
        watchHealth.removeAll()
    }

    /// Cancel just the named cluster's watch (used on disconnect and on reload).
    @MainActor
    func stopWatch(for clusterId: String) {
        watchTasks[clusterId]?.cancel()
        watchTasks[clusterId] = nil
        resourceVersions.removeValue(forKey: clusterId)
        watchHealth.removeValue(forKey: clusterId)
    }
}
