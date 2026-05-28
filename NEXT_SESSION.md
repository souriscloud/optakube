# Next session plan

Shipped: **v0.4.2** (https://github.com/souriscloud/optakube/releases/tag/v0.4.2)
What's deferred from this iteration, ordered by ship-ability.

---

## ✅ DONE in 0.4.2

- **`K8sAPIClient` actor-ish refactor.** Did **option B-variant**, not the full-actor A: extracted a small `TLSTrustDelegate: NSObject, URLSessionDelegate, @unchecked Sendable` that owns the TLS trust state + client identity/cert + the `NSLock`-guarded `lastTLSError`. `K8sAPIClient` itself is now a plain `final class K8sAPIClient: Sendable` with only `let` state — no `@unchecked`, no lock, no `NSObject`. This avoided turning ~15 call sites into `await`. The `@objc(URLSession:didReceiveChallenge:completionHandler:)` workaround is preserved verbatim inside the delegate.
- **`typedWatch` perf.** Added `WatchCoalescer<T>` actor + `applyWatchBatch(...)` `@MainActor` method in `AppViewModel`. Trailing-edge 100ms debounce → one `@Observable` mutation per burst window instead of per event; batch apply uses an id→index map (O(batch + items)). The old `contains`/`firstIndex`/`removeAll` linear scans are gone.
- ⚠️ **Not yet validated against a real busy cluster.** The coalescer is correct by construction (final drain guarantees no stale tail) but nobody has watched a 200-pod startup storm through it yet. If anything looks off, the suspect is `applyWatchBatch` delete-reindex or the `flushTask` lifetime in `typedWatch`.

---

## 0.4.4 — events watch (kill the 5s poll)

**Lowest priority — the poll works.** Only do this if you want the resource savings; not worth risking a working feature otherwise.

- `Sources/OptaKube/Views/Detail/EventsListView.swift:97` polls every 5s while visible
- Kubernetes DOES expose a watch on `/api/v1/namespaces/{ns}/events?fieldSelector=involvedObject.uid={uid}`
- Add `ResourceType.events` case-or-equivalent watch URL builder; reuse `typedWatch` if event model conforms cleanly to `K8sResource`
- Keep `EventBadgeStore` semantics identical — drop-in replacement of the polling loop
- Saves 12 requests/min per open detail view; matters when 5+ tabs are open

---

## 0.5.0 — architecture refactor (multi-hour, own session)

**Big enough to warrant its own beta cut.** Use `--beta` flag on release.sh.

### Split AppViewModel (564 lines, god-object)

Suggested decomposition:
- `ConnectionStore` — `activeClients: [String: K8sAPIClient]`, connect/disconnect, watch task ownership
- `NamespaceStore` — selected namespace per cluster, namespace lists
- `ResourceCache` — the typed arrays (pods, deployments, etc.) keyed by clusterId
- `AutoRefreshCoordinator` — the timer + which clusters need polling fallback

Wire these as `@Observable` types passed via `.environment(...)` from `MainWindow`. **Don't make them singletons.** Per-window instances; that's the whole point.

### Reduce singletons

Current `.shared`s and what to do with each:

| Singleton | Verdict |
|---|---|
| `ClusterStore.shared` (`AppViewModel.swift:8`) | **Keep.** Genuinely app-wide kubeconfig state. |
| `WindowManager.shared` | **Keep.** App-level window registry. |
| `UpdateController.shared` | **Keep.** Wraps Sparkle which is itself singleton-shaped. |
| `PortForwardManager.shared` | **Keep but inject via environment.** App-wide but views should `@Environment(PortForwardManager.self)` it. |
| `ClusterCustomizationStore.shared` | **Inject via environment.** Same shape as above. |
| `RecentsStore.shared` | **Inject via environment.** |
| `NotificationsService.shared` | **Keep.** Cross-cluster, app-scoped. |
| `EventBadgeStore.shared` (`EventsListView.swift:7`) | **Move into AppViewModel split (ResourceCache).** It's per-cluster state. |
| `TerminalBridge.shared` | **Keep.** Tied to the single footer terminal. |
| `LogWindowHolder.shared` (`LogStreamView.swift:1164`) | **Keep.** Tied to NSWindow lifecycle. |

The wins are surgical (~3 stores), not a wholesale anti-singleton crusade.

---

## Backlog (uncommitted — discuss before doing)

- **Diff for StatefulSet / DaemonSet revisions.** Same shape as the Deployment diff in `RevisionDiffView.swift`. StatefulSet uses `controller-revision-hash`; DaemonSet has `ControllerRevision` resources. ~1h.
- **Watch reconnect telemetry in StatusBar.** Show "reconnected 3x in last hour" — surfaces flaky clusters before they cause grief.
- **Resource diff against arbitrary YAML.** Drop a YAML file on a resource → side-by-side diff against live. Reuses `RevisionDiffView`'s diff engine.
- **Bulk actions.** Select multiple pods → delete / restart parent deployment. Already half there (right-click context menus exist).

---

## Pre-flight on resume

```bash
git log --oneline -5
git tag --sort=-v:refname | head -3
swift build  # confirm clean build before touching anything
```

If `swift build` is clean and the last tag is `v0.4.1`, start on 0.4.2 (actor refactor).
