# Next session plan

Shipped: **v0.4.1** (https://github.com/souriscloud/optakube/releases/tag/v0.4.1)
What's deferred from this iteration, ordered by ship-ability.

---

## 0.4.2 — actor-ify K8sAPIClient (smallest, ship first)

**Goal:** drop `@unchecked Sendable` + `NSLock` on `K8sAPIClient`. ~30–60 min focused.

- `Sources/OptaKube/Services/K8sAPIClient.swift:776 lines`
- Currently `final class K8sAPIClient: @unchecked Sendable` with manual `NSLock` guarding `lastTLSError`
- Two viable shapes:
  - **A. Convert to `actor K8sAPIClient`** — natural fit, but every callsite becomes `await`. Audit: ~15 call sites across `AppViewModel`, `RevisionDiffView`, `EventsListView`, `LogStreamView`, `PortForwardService`. Most are already `await`-able.
  - **B. Keep class, replace `NSLock` with an internal `actor` for the mutable bits** — less call-site churn. The only mutable state is `lastTLSError` (and identity from PKCS12 import).
- **Recommendation: A.** The class is mostly `async` already; explicit actor isolation is cleaner than a hybrid.
- **Gotchas:**
  - `URLSessionDelegate` methods must stay non-isolated (URLSession invokes them on its own queue). Keep them as a separate `class TrustDelegate: NSObject` that captures the actor weakly and `Task { await actor.recordTLSError(...) }` from the delegate.
  - The `@objc(URLSession:didReceiveChallenge:completionHandler:)` selector survives whole-module opt — do NOT remove that workaround.
- **Test:** reconnect to an EKS cluster + a self-signed cluster + run log streaming for 5+ min. No regressions on the 0.3.3 TLS fix.

---

## 0.4.3 — perf hotspots in `typedWatch`

Cheap, isolatable wins. Independent of the actor refactor.

- `Sources/OptaKube/ViewModels/AppViewModel.swift:441` `typedWatch<T>`
  - Line 456: `if !items.contains(where: { $0.id == event.object.id })` — O(N) per ADDED
  - Line 460: `firstIndex(where:)` — O(N) per MODIFIED
  - implicit `removeAll(where:)` for DELETED — O(N) per event
- Replace with a parallel `[String: Int]` id→index dict maintained alongside the array. Mutations stay O(1), the array stays as the SwiftUI source-of-truth.
- **Burst mitigation:** add a 50–100ms debounce that coalesces multiple watch events into a single `@Observable` notification. Right now a Pod startup storm (200 pods all going Pending→Running over 2s) re-renders the table 200 times.
- **Measure first.** Use Instruments → SwiftUI template, scenario: connect to a busy cluster, time-profile while pods are flapping. Don't optimize until the trace shows it matters.

---

## 0.4.4 — events watch (kill the 5s poll)

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
