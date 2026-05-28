import Foundation

// MARK: - Live Updates: Watch Engine & Auto-Refresh
//
// The push side of the resource lifecycle. One watch task per cluster streams
// ADDED/MODIFIED/DELETED events and applies them to the resource cache; bursts are
// coalesced (see `WatchCoalescer`) so a startup storm is one re-render per ~100ms
// window rather than one per event. `startAutoRefresh` is a polling fallback only for
// clusters/types that don't have an active watch.

extension AppViewModel {
    func startAutoRefresh(interval: TimeInterval = 30) {
        refreshTask?.cancel()
        refreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                // Fallback poll for any selected cluster that doesn't have an active watch.
                // The watch path handles the typical case; this catches resource types
                // that aren't yet wired into runWatch's switch (default branch sleeps 30s)
                // and any cluster whose watch hit its retry cap.
                let unwatched = selectedClusterIds.subtracting(watchTasks.keys)
                if unwatched.isEmpty == false {
                    await refresh()
                }
            }
        }
    }

    func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    func startWatch(for clusterId: String) {
        watchTasks[clusterId]?.cancel()
        watchTasks[clusterId] = nil
        guard let client = activeClients[clusterId] else { return }
        let type = selectedResourceType
        let ns = type.isNamespaced ? selectedNamespace : nil

        let task = Task.detached { [weak self] in
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
        watchTasks[clusterId] = task
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

        for try await event in stream {
            let shouldSchedule = await coalescer.add(event)
            if shouldSchedule {
                flushTask = Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(100))
                    let batch = await coalescer.drain()
                    if !batch.isEmpty {
                        await self?.applyWatchBatch(batch, cid: cid, kp: kp)
                    }
                }
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
            if let rv = obj.metadata.resourceVersion { latestRV = rv }
        }

        self[keyPath: kp][cid] = items
        if let rv = latestRV { resourceVersions[cid] = rv }
    }

    func stopWatch() {
        for (_, task) in watchTasks { task.cancel() }
        watchTasks.removeAll()
        resourceVersions.removeAll()
    }

    /// Cancel just the named cluster's watch (used on disconnect).
    func stopWatch(for clusterId: String) {
        watchTasks[clusterId]?.cancel()
        watchTasks[clusterId] = nil
        resourceVersions.removeValue(forKey: clusterId)
    }
}
