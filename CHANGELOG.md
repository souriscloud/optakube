# Changelog

All notable changes to OptaKube will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.6.0] - 2026-05-30

### Added
- **Helm releases.** A "Helm" section in the sidebar lists Helm v3 releases (latest revision per release) across connected clusters, with status, chart, app version, and update time. Inspect any release for its info, user-supplied values, rendered manifest, and full revision history. Decoded directly from the `owner=helm` release Secrets (base64 → base64 → gunzip → JSON) — no `helm` binary required. *(Rollback/uninstall are not yet wired.)*
- **Create resources from YAML.** A `+` toolbar button (⌘N) opens an editor: paste a manifest and apply it with **server-side apply** (create-or-update, idempotent). Routes by the manifest's `apiVersion`/`kind`, resolving against built-in types and discovered CRDs.
- **Twelve new resource types.** RBAC — Roles, RoleBindings, ClusterRoles, ClusterRoleBindings — plus StorageClasses, ResourceQuotas, PodDisruptionBudgets, LimitRanges, PriorityClasses, Leases, and Mutating/ValidatingWebhookConfigurations, each with a purpose-built table. They inherit the existing YAML view/edit/diff/apply and delete actions for free.
- **Cluster-wide events view.** A "Tools → Events" browser shows every event in the selected namespace (or all namespaces) across connected clusters, newest first, with a Warnings-only toggle and a warning count — a triage firehose alongside the existing per-resource events.
- **Bulk actions.** Multi-select rows in any resource table; a bottom action bar offers bulk **Delete** (with confirmation) and bulk **Restart** (for Deployments/StatefulSets/DaemonSets). The inspector still opens when exactly one row is selected.
- **CRD instance editing.** Discovered custom resources are no longer browse-only: a context-menu "Edit YAML…" opens a sheet with view/edit/diff/apply and delete, matching the built-in types.
- **Ko-fi support link** in the status-bar footer (centralized with the About link).

### Internal
- Test target grows to 39 (added: Helm gzip inflate against a real fixture, `ResourceType.kind` manifest-routing round-trip, and group/scope checks for the new types).

## [0.5.0] - 2026-05-30

### Added
- **Label-selector filter.** A filter field in the resource list toolbar accepts a Kubernetes label selector (`app=web,tier!=db,env in (prod,stage)`, plus existence `release` / non-existence `!canary`) and narrows rows live, on top of the existing name search. Multiple clauses are ANDed; an invalid clause is flagged (red) without hiding everything, and the bar stays visible when a filter matches zero rows so you can always clear it
- **Saved views (Favorites).** Pin the current namespace + resource type + label filter from the toolbar star; pinned views appear in a Favorites section in the sidebar and jump straight back with one click. Stored globally so they're available in every window/cluster
- **Access review (`can-i`).** A new toolbar button runs `SelfSubjectAccessReview` for the connected credentials across every resource type × common verb (get/list/watch/create/update/delete) in the selected namespace, rendered as a check/✗ matrix — `kubectl auth can-i --list` as a readable grid. Always works for the current user (no extra RBAC needed)
- **Diff before YAML apply.** Editing a resource's YAML and hitting *Review & Apply* now shows a unified line diff (added/removed, with context) for confirmation before the `PUT` lands, instead of applying blind

### Internal
- First test target (`OptaKubeTests`, 32 tests): label-selector parsing/matching, `ResourceType` API-group + URL construction, `SavedView`/`WindowState` codable round-trips, and the YAML unified-diff engine. Run with `swift test`

## [0.4.5] - 2026-05-29

### Fixed
- **Crash on connect when running unbundled (`swift run` / raw SPM binary).** `UNUserNotificationCenter.current()` hard-asserts (`bundleProxyForCurrentProcess is nil`) without an app bundle; it fired the moment a pod list loaded successfully (`observe(pods:)` → `ensureAuthorization`), aborting the app. The shipped, notarized `.app` was never affected (it has a bundle) — this only bit the dev workflow. Notification-center calls are now gated behind a bundle check, the same way Sparkle already is

## [0.4.4] - 2026-05-29

### Internal
- **Split `AppViewModel` into concern-focused files.** The 610-line god-object is now four files — core state + connection lifecycle (`AppViewModel.swift`), list loading + CRDs + metrics (`AppViewModel+Resources.swift`), the watch engine + auto-refresh (`AppViewModel+Watch.swift`), and state persistence (`AppViewModel+Persistence.swift`) — kept as a single `@Observable` type via extensions. No view-facing API change, identical runtime behavior; just navigability

## [0.4.3] - 2026-05-29

### Changed
- **Events tab is now live via a watch instead of a 5s poll.** On open it lists the resource's events once (for the initial render) and captures the list `resourceVersion`, then holds an open watch from that point — applying ADDED/MODIFIED/DELETED in place as they arrive. The server periodically closes long-lived watches and may expire the resourceVersion (410 Gone); both just loop back to a fresh list + re-watch, with exponential backoff on hard failures. Lower request volume (no fixed relist every 5s when nothing changes) and events appear the moment Kubernetes records them
- Factored the watch streaming into a shared `streamWatch(watchURL:)` so the events watch and the resource watch share one code path

## [0.4.2] - 2026-05-29

### Changed
- **Smoother live updates on large namespaces.** The watch consumer now coalesces bursts of events on a ~100ms trailing-edge window and applies them as a single batch. Previously every watch event (ADDED/MODIFIED/DELETED) triggered its own `@Observable` mutation — so a startup storm of hundreds of pods flipping Pending→Running re-rendered the whole table once per pod. Now it's one re-render per ~100ms window. Steady-state single updates still appear within 100ms; a final drain when the stream ends guarantees nothing is left stale
- Batch apply builds an id→index map, so applying a watch batch is O(batch + items) instead of O(batch × items) — the per-event `contains` / `firstIndex` linear scans are gone

### Internal
- **`K8sAPIClient` is now a clean `Sendable` type** instead of `@unchecked Sendable` with a manual `NSLock`. All TLS trust + client-identity state moved into a small dedicated `TLSTrustDelegate` (the one piece that genuinely needs `@unchecked Sendable`, because URLSession invokes it off its own delegate queue). The client itself now has only immutable `let` state. The `@objc` completion-handler workaround that fixed the 0.3.2 release-build TLS regression is preserved verbatim in the delegate

## [0.4.1] - 2026-05-28

### Added
- **Diff tab on Deployments.** Lists historical ReplicaSet revisions; selecting one renders a side-by-side YAML diff of the pod template against the live deployment, with red highlighting for removed/changed lines on the left and green for inserts/changes on the right. What you reach for before clicking Rollback
- **Events tab: live updates.** Re-polls events every 5 seconds while the tab is visible (Kubernetes doesn't expose a per-resource subscription, so polling is the right shape here). Plus a warning-count badge on the tab title — visible from the Overview tab too, so you don't have to click in to notice new failures

### Fixed
- **Live updates across multiple clusters.** `watchTask` was singular: loading a second cluster's resources cancelled the first cluster's watch, so only the most-recently-loaded cluster received ADDED/MODIFIED/DELETED events. Now one watch per cluster — every connected cluster gets live updates simultaneously
- Watch cancellation on disconnect now scopes to just that cluster instead of being implicit via the singular task being overwritten

## [0.4.0] - 2026-05-28

### Added
- **Beta channel.** Settings → Updates lets you switch between Release (default) and Beta. Beta builds publish to `appcast-beta.xml`; Sparkle picks the feed dynamically via the SPUUpdaterDelegate
- **Pod restart notifications.** When a watched pod's restart count goes up, OptaKube posts a system notification (Settings → Updates → "Notify on pod restart" to disable). Requires Notifications permission on first restart event
- **Recently used resources in Cmd+K.** Empty-query palette now shows the last 5 resources you opened from a connected cluster, with a clock icon to distinguish from live search hits. Stored in UserDefaults, bounded to 20 entries

### Changed
- **release.sh `--dry-run`.** Builds, signs, notarizes, staples, and Sparkle-signs the DMG without pushing to git or creating a GitHub release. Lets you verify locally before publishing
- **release.sh `--beta`.** Updates `appcast-beta.xml` instead of `appcast.xml` and marks the GitHub release as a pre-release
- **Menu-bar dropdown file/struct renamed** from `PortForwardMenuBarView` → `MenuBarDropdownView` (it's been the whole unified menu since 0.3.1)
- **`ClusterConnection.kubeconfigPath` / `.splitID()`** helpers replace three duplicated copies of `id.split(":", maxSplits: 1)` across the codebase

### Fixed
- All compiler warnings: unused `var`, unused bindings, Swift-6 main-actor isolation warnings in `SpotlightSearch.preloadAllResources` (case-pattern `where` clauses are nonisolated autoclosures and couldn't read the view model)
- Removed empty `Sources/OptaKube/Extensions` and `Sources/OptaKube/Utilities` directories
- Unused `let status` in StatusBar, unused `let template` / `let url` / `let ctx` in K8sAPIClient and MainWindow

## [0.3.3] - 2026-05-28

### Fixed
- EKS / custom-CA TLS rejection in shipped .app builds, take three. ATS in a notarized .app applies its own policy checks (TLS minimum version, cert algorithm, etc.) AFTER the URLSession delegate approves the server trust — and rejects Kubernetes API servers signed by self-managed cluster CAs regardless of our SecTrust pinning. The Info.plist now declares `NSAppTransportSecurity → NSAllowsArbitraryLoads`, letting our existing custom-CA verification (via `SecTrustEvaluateWithError`) actually take effect. This is why TLS worked under `swift run` (no ATS) but every shipped .app since v0.2.0 fell back to the generic "A TLS error caused the secure connection to fail"
- Transport errors now include the URLError code in the banner (e.g. `[URLError -1200]`) so we're never blind again to which class of failure URLSession reported

## [0.3.2] - 2026-05-28

### Fixed
- EKS / custom-CA TLS rejection in release builds. The URLSession challenge delegate was written as an `async -> (...)` method, which relies on Swift's ObjC bridge that whole-module optimisation in release builds can strip. URLSession's `responds(to:)` then returned false and it fell back to default handling — which rejects custom CAs and surfaces the generic "A TLS error caused the secure connection to fail". Switched to the explicit `@objc` completion-handler signature so the selector is always exported, regardless of optimisation level. This is why TLS worked under `swift run` but failed in shipped .app installs.

## [0.3.1] - 2026-05-28

### Changed
- Menu-bar-icon dropdown is now a native macOS menu (was a custom popover) and unified with the app menu: Welcome, open cluster windows, port forwards, About, Check for Updates, Settings, Quit
- Sparkle ownership moved into a single `UpdateController.shared` singleton; both the app menu and the menu-bar icon route through it

### Fixed
- "Check for Updates…" is now always discoverable. Previously it lived only inside the cluster `WindowGroup`'s command menu, so it disappeared when no cluster window was focused — and was hidden entirely when the bundle had no `CFBundleIdentifier`. Now visible in both the app menu and the menu-bar-icon dropdown, disabled when Sparkle isn't available (e.g. `swift run`)
- Removed duplicate "Connect to Cluster…" + "Welcome Screen" entries that did the same thing

## [0.3.0] - 2026-05-28

### Added
- Exec Shell — right-click any pod → "Exec Shell" runs `kubectl exec -it … -- bash` (with sh fallback) inside the footer terminal, dropping you into the container's shell while keeping your fish/zsh session alive when you exit
- Footer terminal auto-detects fish at `/opt/homebrew/bin/fish` or `/usr/local/bin/fish` even when login `SHELL` points elsewhere
- Settings → Appearance → Terminal → Shell: override which shell the footer terminal launches (fish / zsh / bash / sh / auto)

### Changed
- Build number is now derived from the version (`major*10000 + minor*100 + patch` → 0.3.0 = 300). Single source of truth, no manual increment, no drift between displayed version and bundle metadata
- `release.sh <version>` updates the Swift constant in `AboutView.swift` and `Info.plist` in one pass; rejects non-`X.Y.Z` input upfront
- Fish in the footer launches as a real login shell (`--login`, argv0 `-fish`) so login-only conf.d fragments — including AWS env exports — actually run

### Fixed
- TLS handshake against EKS now surfaces the real failure reason. Previously every TLS failure showed the generic "A TLS error caused the secure connection to fail"; now you see "TLS: server trust for …: <actual reason>" — chain issue, hostname mismatch, parse failure, etc.
- Server-trust path explicitly calls `SecTrustEvaluateWithError` after pinning the kubeconfig CA, instead of returning an unevaluated trust to URLSession
- Log viewer: enabling a previously-disabled container actually starts its stream (was a silent no-op); disabling cancels its stream
- Log viewer: history merge no longer renumbers line IDs, so active search match navigation stays correct after late-arriving history flushes; marks also stay at their original timestamp position instead of being moved to the end
- Log viewer: JSON syntax highlighter no longer double-prints the first letter of `true` / `false` / `null` (was rendering `truet`, `falsef`, `nulln`)
- Version display: footer / About now reads from a compiled-in constant instead of `Bundle.main.infoDictionary`, fixing the v0.1.0 fallback under non-bundled runs

## [0.2.0] - 2026-03-31

### Added
- Full-window log viewer — right-click pod → "Open Logs" or click "Logs" button in detail header
- Open logs in separate standalone window (not a cluster window)
- JSON syntax highlighting in log lines (keys, values, numbers, booleans color-coded)
- logfmt syntax highlighting (key=value pairs color-coded)
- ANSI escape code stripping for clean log display
- Line wrap toggle in log viewer
- Search with highlight + forward/back navigation (Cmd+G / Shift+Cmd+G)
- Filter or Highlight search mode toggle
- Press Space to insert visual mark separator while watching logs
- Pod/container selector with individual checkboxes (enable/disable per container)
- Init container logs support (shown in container picker, disabled by default)
- Timestamp display options: Local / UTC / Off
- Log font size: Small / Default / Large
- Auto-reconnect with retry backoff on log stream disconnect
- Live streaming indicator in log status bar
- Server-side timestamps for proper chronological ordering of multi-pod logs
- Cluster color and rename customization (persisted, reflected instantly everywhere)
- Customize button in welcome screen per cluster
- App version and last refresh time shown in status bar
- "Open Logs" in right-click context menu for pods

### Changed
- Log viewer completely rewritten with professional UX
- Removed Logs tab from detail sidebar (replaced by dedicated log views)
- Scroll behavior: stays at user's position when reading, auto-scrolls only when at bottom
- Pod picker popover enlarged (shows 7+ pods without scrolling)
- Adding a pod to log stream now immediately starts streaming
- App icon properly sized with Apple HIG 10% margins (matches other Dock icons)
- Sparkle only initializes when running in proper app bundle (no more crash in debug)
- Watch API uses exponential backoff (3s → 9s → 27s) instead of constant 3s retry

### Fixed
- Multi-pod historical logs now sorted chronologically (using K8s server-side timestamps)
- Tables with few rows no longer center — pinned to top
- Spotlight search scroll follows keyboard selection
- Watch stream no longer floods logs with TLS errors on self-signed clusters

## [0.1.0] - 2026-03-25

### Added

**Core**
- Native macOS Kubernetes GUI built with Swift and SwiftUI
- Multi-window architecture — one window per cluster, independent state
- JetBrains-style welcome window with cluster discovery, import, and connection testing
- Auth: kubeconfig tokens, client certificates (EC + RSA), exec-based (AWS EKS, GCP GKE)
- Custom CA certificate trust for self-signed clusters
- Per-cluster state persistence (namespace, resource type survive restarts)

**Resources**
- 20+ built-in resource types: Pods, Deployments, Services, Nodes, StatefulSets, DaemonSets, ReplicaSets, Jobs, CronJobs, ConfigMaps, Secrets, Ingresses, IngressClasses, PersistentVolumes, PersistentVolumeClaims, NetworkPolicies, ServiceAccounts, HorizontalPodAutoscalers, Namespaces, Endpoints
- CRD auto-discovery — browse any Custom Resource Definition installed on the cluster
- Watch API for real-time resource updates with automatic reconnection
- Inline CPU/Memory metrics in Pod and Node tables (metrics-server integration)
- Resource detail views with container-level tabs, probes, env vars, volume mounts
- Environment variable unwrapping — reveal actual Secret/ConfigMap values with one click
- YAML editor with syntax highlighting and apply (edit resources in-place)

**Actions**
- Restart, scale, rollback deployments (with revision history)
- Port forwarding with pod port discovery
- Debug/ephemeral containers with common image picker
- CronJob trigger, suspend, resume
- Node cordon, uncordon, drain
- Pod eviction
- Right-click context menus on all resource types
- Copy name, copy full name, copy kubectl command

**UX**
- Spotlight search (Cmd+K) — search across all resources, namespaces, types, CRDs
- Embedded terminal (SwiftTerm) with full PTY, inherits KUBECONFIG and context
- Cluster overview dashboard — node status, resource summary, events, utilization charts
- Collapsible sidebar categories and detail/inspector panel (Cmd+D)
- Log streaming with multi-pod aggregation, search, timestamps, export
- Cluster color and rename customization (reflected everywhere instantly)
- Status bar with connection info, resource count, last refresh time, version
- Menu bar icon with window management, port forward controls, quick actions
- Keyboard shortcuts (Cmd+1-9 resource types, Cmd+R refresh, Cmd+Shift+T terminal)
- Auto-updates via Sparkle framework

**Distribution**
- Release script (scripts/release.sh) for automated builds, DMG creation, and GitHub releases
- Sparkle appcast for auto-updates
