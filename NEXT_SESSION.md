# Next session plan

Shipped: **v0.4.3** (https://github.com/souriscloud/optakube/releases/tag/v0.4.3)
Open PR: **#1** (https://github.com/souriscloud/optakube/pull/1) — AppViewModel file split, awaiting real-cluster validation.

---

## ✅ DONE

### v0.4.2
- **`K8sAPIClient` is now `Sendable` (no `@unchecked`, no lock).** Extracted a small `TLSTrustDelegate: NSObject, URLSessionDelegate, @unchecked Sendable` that owns TLS trust + client identity/cert + the `NSLock`-guarded `lastTLSError`. The client itself has only `let` state now. The `@objc(URLSession:didReceiveChallenge:completionHandler:)` workaround is preserved verbatim in the delegate.
- **Watch coalescing.** `WatchCoalescer<T>` actor + `applyWatchBatch(...)` (now in `AppViewModel+Watch.swift`). Trailing-edge 100ms debounce → one `@Observable` mutation per burst window; batch apply uses an id→index map.

### v0.4.3
- **Events tab is live via a watch** (`EventsListView.swift`), not a 5s poll. Lists once for the initial render + captures resourceVersion, then watches from there with relist-on-410 + exponential backoff. New client methods: `listEventsForResourceWithVersion`, `watchEventsForResource`, and a shared `streamWatch(watchURL:)` factored out of `watch(...)`.

### PR #1 — AppViewModel file split (NOT yet merged)
- 610-line `AppViewModel.swift` → 4 files (core / +Resources / +Watch / +Persistence), still one `@Observable` type. Pure code movement, build-clean, every method verified present exactly once.
- **⚠️ Needs `swift run` against a real cluster before merge.** Behavior-neutral by construction but touches the live-update hot path.

---

## Deliberately NOT done (and why) — the deeper 0.5.0

After reading the actual coupling, I recommend **against** these unless a concrete maintenance pain shows up. Recorded here so the reasoning isn't lost:

- **Split into separate `@Observable` stores** (ConnectionStore / ResourceCache / etc.): the 20 resource dicts are read directly by views (`viewModel.pods`) *and* written by the watch engine via `ReferenceWritableKeyPath<AppViewModel, …>`. Moving them breaks dozens of view read-sites + every keyPath write-site, needs `.environment()` injection at every `WindowGroup` (missed injection = runtime crash), and can't be validated without launching every window against a live cluster. High churn, zero user benefit.
- **Convert singletons to environment injection** (`PortForwardManager`, `ClusterCustomizationStore`, `RecentsStore`, `EventBadgeStore`): these are an idiomatic SwiftUI pattern here. Converting is taste-driven, adds crash risk, and buys only testability — not worth it for this app.

The file split in PR #1 captures the real, safe core ("the god-object file is hard to navigate") without the risk.

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
git tag --sort=-v:refname | head -3   # latest should be v0.4.3
gh pr view 1                          # the AppViewModel split, pending validation
swift build  # confirm clean build before touching anything
```

First thing on resume: validate PR #1 against a real cluster (`git checkout refactor/split-appviewmodel && swift run`), then merge or report issues. After that, the remaining backlog below is the menu.
