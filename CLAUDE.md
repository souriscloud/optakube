# OptaKube

A free, native macOS Kubernetes GUI client built with Swift and SwiftUI.

## Project Structure

- `Package.swift` — SPM manifest (dependencies: Yams, SwiftTerm, Sparkle)
- `Sources/OptaKube/` — All source code
  - `Models/` — Data models (KubeConfig, K8s resources, CRDs, Metrics, ResourceType, ResourceStatus, LabelFilter, ManifestRouting, ManifestYAML, ClusterCustomization)
  - `Services/` — Backend services (KubeConfigService, K8sAPIClient, K8sAuthProvider, PortForwardService, UpdateController, NotificationsService, RecentsStore, GitHubFeedback)
  - `ViewModels/` — State management (ClusterStore + AppViewModel in `AppViewModel.swift`, its `+Resources`/`+Watch`/`+Helm`/`+Persistence` extensions, WindowManager, SavedViewsStore)
  - `Views/` — SwiftUI views (Welcome, Sidebar, Content, Detail, Logs, Actions, Settings, Components)
  - `Resources/` — App icon (AppIcon.icns)
- `Tests/OptaKubeTests/` — XCTest suite (`swift test`)
- `scripts/release.sh` — Build, sign, notarize, appcast, publish. See `scripts/RELEASE-GUIDE.md`
- `appcast.xml` — The live Sparkle feed. Served from this branch, so a bad commit reaches every install
- `.github/workflows/ci.yml` — Build + test + version/appcast consistency on macOS
- `CHANGELOG.md` — Keep a Changelog format; add entries under `[Unreleased]`
- `CONTRIBUTING.md`, `SECURITY.md`, `CLAUDE.md` — Docs

## Tech Stack

- **Swift + SwiftUI** targeting macOS 14+ (Sonoma)
- **URLSession** for Kubernetes API communication (no third-party HTTP libs)
- **Security.framework** for TLS client certificates and custom CA trust
- **openssl** subprocess for PEM→PKCS12 conversion (handles EC + RSA keys)
- **@Observable** macro for state management (no Combine)
- Three external deps only: **Yams** (kubeconfig + manifest YAML), **SwiftTerm**
  (embedded terminal), **Sparkle** (auto-update)
- **Swift Charts** for metrics

## Build & Run

```bash
swift build          # CLI build
swift test           # Run the test suite
swift run            # Build and run
open Package.swift   # Open in Xcode, Cmd+R to run
```

`swift run` launches the raw binary, not an app bundle. Sparkle and
`UNUserNotificationCenter` both require a bundle and deliberately no-op without one, so
auto-update and notifications can only be exercised from a packaged build.

## Architecture

### Window Model (JetBrains-style)
- **Welcome Window** — hub window, always the entry point. Cluster discovery, import, test, connect.
- **Cluster Windows** — one per connection session. Each has its own AppViewModel.
- **Lifecycle**: Welcome → select clusters → Connect → cluster window opens, welcome hides → close last cluster window → welcome reappears.

### State Layers
- **ClusterStore** (singleton) — shared kubeconfig paths/dirs, cluster discovery. Used by all windows and Settings.
- **WindowManager** (singleton) — tracks active cluster windows, creates/destroys per-window AppViewModels.
- **AppViewModel** (per-window) — cluster connections, namespace, resource type, resource data, auto-refresh.

### Persistence
- **Kubeconfig sources** — `UserDefaults` keys `kubeConfigPaths`, `kubeConfigDirs`
- **Per-cluster state** — keyed by sorted cluster IDs (e.g. `clusterState.id1+id2`). Stores namespace, resource type.
- **Window frame** — macOS native `setFrameAutosaveName`

### Auth
- Reads `$KUBECONFIG` (colon-separated) or `~/.kube/config`, plus custom paths/directories
- **Token auth** — Bearer token header; `tokenFile` is read from disk
- **Client certificate** — PEM cert+key → PKCS12 via `/usr/bin/openssl` → `SecPKCS12Import` → `SecIdentity` for TLS. Both embedded (`*-data`) and file-path forms, with relative paths resolved against the kubeconfig's directory
- **Exec auth** — runs command via user's login shell (`zsh -l -c "aws ..."`) for full PATH. Caches the token, renewing 60s before expiry, with a 5-minute fallback when the plugin returns none. Pipes are drained concurrently before waiting for exit (the reverse order deadlocks past 64KB of output) with a 60s watchdog. A 401 on a token believed valid invalidates the cache and retries once
- **Unsupported modes** (`auth-provider`, basic auth) resolve to `.unsupported(reason)` so the UI names the problem rather than issuing an anonymous request and reporting the 401

### Live updates
Watches always end — the server closes them routinely, sleep leaves half-open sockets,
resourceVersions expire. So every exit path in `AppViewModel+Watch.swift` either reconnects
or records `WatchHealth`, and the task always deregisters from `watchTasks`; the polling
fallback keys off health, never off dictionary membership. An expired resourceVersion
arrives as an in-stream `ERROR`/`Status` line far more often than as an HTTP 410, and both
trigger a relist. `timeoutSeconds` is sent on every watch so a dead socket can't
masquerade as a live one.

### Layout
- `NavigationSplitView` — sidebar (resource types) + detail area
- Detail area: `HStack` of resource list (fills space) + optional inspector panel
- Inspector panel: toggled via Cmd+D, auto-opens on resource selection

## Conventions

- All K8s resource models conform to `K8sResource` protocol
- `ResourceType` enum maps each resource to its API group, path, SF Symbol, category, and `kind`
- `ResourceStatus` enum with color-coded status indicators
- Row wrapper structs conforming to `ResourceRow` protocol for Table selection
- Async/await throughout, `@MainActor` for UI updates
- **A new resource type must be added in all seven places** — model, `ResourceType` case,
  `AppViewModel` storage + list switch + `clearResources`, `runWatch` case, table,
  `*DetailContent` view, `StatusBar` count, `SpotlightSearch` case. Missing the last four
  is what previously left 21 of 32 types with no live updates, no detail view, a count of
  zero, and invisible to ⌘K. `CONTRIBUTING.md` has the checklist
- **Errors must reach the user.** A bare `try?` around anything that mutates cluster state
  is a bug: it renders an RBAC denial indistinguishable from success
