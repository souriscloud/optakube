# OptaKube

A free, native macOS Kubernetes GUI client built with Swift and SwiftUI.

## Project Structure

- `Package.swift` — SPM manifest (dependencies: Yams, SwiftTerm)
- `Sources/OptaKube/` — All source code
  - `Models/` — Data models (KubeConfig, K8s resources, CRDs, Metrics, ResourceType, ResourceStatus)
  - `Services/` — Backend services (KubeConfigService, K8sAPIClient, K8sAuthProvider, PortForwardService)
  - `ViewModels/` — State management (ClusterStore singleton, AppViewModel per-window, WindowManager)
  - `Views/` — SwiftUI views (Welcome, Sidebar, Content, Detail, Logs, Actions, Settings, Components)
  - `Resources/` — App icon (AppIcon.icns)
- `PROJECT.md` — Development progress tracker
- `CLAUDE.md` — This file

## Tech Stack

- **Swift + SwiftUI** targeting macOS 14+ (Sonoma)
- **URLSession** for Kubernetes API communication (no third-party HTTP libs)
- **Security.framework** for TLS client certificates and custom CA trust
- **openssl** subprocess for PEM→PKCS12 conversion (handles EC + RSA keys)
- **Yams** (only external dep) for kubeconfig YAML parsing
- **@Observable** macro for state management (no Combine)

## Build & Run

```bash
swift build          # CLI build
swift run            # Build and run
open Package.swift   # Open in Xcode, Cmd+R to run
```

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
- Reads `~/.kube/config` and custom paths/directories
- **Token auth** — Bearer token header
- **Client certificate** — PEM cert+key → PKCS12 via `/usr/bin/openssl` → `SecPKCS12Import` → `SecIdentity` for TLS
- **Exec auth** — runs command via user's login shell (`zsh -l -c "aws ..."`) for full PATH. Caches token until expiry. Captures stderr for error messages.

### Layout
- `NavigationSplitView` — sidebar (resource types) + detail area
- Detail area: `HStack` of resource list (fills space) + optional inspector panel
- Inspector panel: toggled via Cmd+D, auto-opens on resource selection

## Conventions

- All K8s resource models conform to `K8sResource` protocol
- `ResourceType` enum maps each resource to its API group, path, SF Symbol, and category
- `ResourceStatus` enum with color-coded status indicators
- Row wrapper structs conforming to `ResourceRow` protocol for Table selection
- Async/await throughout, `@MainActor` for UI updates
