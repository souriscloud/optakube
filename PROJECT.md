# OptaKube — Development Progress

## Status Key
- [ ] Not started
- [~] In progress
- [x] Complete

---

## Phase 1: Foundation (MVP Core)
- [x] Project setup (SPM package, Yams dependency)
- [x] KubeConfig Codable models (clusters, contexts, users, exec)
- [x] KubeConfigService (parse files, parse directories, merge contexts)
- [x] Auth: Token-based auth
- [x] Auth: Client certificate auth (PEM → PKCS12 via openssl, EC + RSA keys)
- [x] Auth: Exec-based auth (login shell for PATH, stderr capture, token caching)
- [x] TLS configuration (custom CA certs, client certs, insecure skip)
- [x] K8sAPIClient (list, get, delete, patch, scale, restart)
- [x] Pod Codable model with full spec/status
- [x] NavigationSplitView layout (sidebar + content + collapsible detail)
- [x] Pod list table view with status badges
- [x] Sidebar with connected clusters + grouped resource types
- [x] Namespace picker
- [x] Search/filter toolbar
- [x] Auto-refresh (configurable interval)

## Phase 2: Full Resource Coverage
- [x] Deployment model + table view (ready, up-to-date, available)
- [x] Service model + table view (type, cluster IP, ports)
- [x] Node model + table view (roles, version, status)
- [x] StatefulSet model + table view (ready/replicas)
- [x] DaemonSet model + table view (desired, ready)
- [x] ReplicaSet model + table view (ready/replicas)
- [x] Job model + table view (completions, duration)
- [x] CronJob model + table view (schedule, suspended, last run)
- [x] ConfigMap model + table view (data key count)
- [x] Secret model + table view (type, data key count)
- [x] Sidebar grouped by category (Workloads, Networking, Config, Cluster)
- [x] Settings: kubeconfig path management (files + directories)
- [x] Settings: appearance (refresh interval, max log lines)

## Phase 3: Detail Views & Actions
- [x] Pod detail view (containers, status, conditions, IPs, node)
- [x] Deployment detail view (replicas, strategy, conditions)
- [x] Service detail view (type, cluster IP, ports, selector)
- [x] Node detail view (roles, version, capacity, conditions, system info)
- [x] StatefulSet detail view (replicas, service name, selectors)
- [x] DaemonSet detail view (desired, ready, available, selectors)
- [x] ReplicaSet detail view (replicas, owner references)
- [x] Job detail view (completions, duration, parallelism, conditions)
- [x] CronJob detail view (schedule, concurrency, active jobs)
- [x] ConfigMap detail view (key-value display)
- [x] Secret detail view (masked values with eye toggle to reveal, base64-decoded)
- [x] Events list for selected resource (filtered by kind/name)
- [x] Quick action: Restart (Deployments, StatefulSets, DaemonSets)
- [x] Quick action: Scale (Deployments, StatefulSets, ReplicaSets)
- [x] Quick action: Delete with confirmation dialog
- [x] YAML viewer (JSON pretty-print, monospaced, selectable)
- [x] YAML syntax highlighting (keys=teal, strings=green, numbers=orange, bools=purple)
- [x] YAML editor with Apply (PUT to API server, JSON validation, success/error feedback)

## Phase 4: Log Streaming
- [x] Single pod log streaming (URLSession.bytes, follow mode)
- [x] Log search with match highlighting
- [x] Container selector for multi-container pods
- [x] Auto-scroll toggle
- [x] Log line cap (10,000 lines)
- [x] Multi-pod log aggregation (10-color palette, pod name pills, add/remove pods)
- [x] Timestamp toggle (HH:mm:ss.SSS)
- [x] Previous container logs (?previous=true, auto-restarts stream)
- [x] Log export (NSSavePanel → .log file with timestamps/pod prefixes)

## Phase 5: Advanced Features
- [x] Watch API for live resource updates (list+watch, auto-reconnect, 410 Gone fallback)
- [x] Port forwarding (via `kubectl port-forward` subprocess, login shell)
- [x] Port forwarding UI (sheet with local/remote ports, pod port discovery, active list)
- [N/A] Multi-cluster merged resource view (using separate windows instead)
- [x] CronJob actions: trigger (creates Job from template), suspend, resume
- [x] Deployment rollback (lists ReplicaSet revisions, rollback by patching template)
- [x] Debug containers (ephemeral container with image picker, common images)

## Phase 6: Window & UX
- [x] Welcome window (JetBrains-style hub — cluster selection, import, test connection)
- [x] Multi-window support (each window = independent cluster session)
- [x] Window lifecycle (welcome → cluster window → close last → welcome reappears)
- [x] Per-cluster state persistence (namespace, resource type survive restarts)
- [x] Collapsible detail/inspector panel (Cmd+D toggle, auto-opens on selection)
- [x] Cluster name truncation in toolbar
- [x] Status bar footer (connection status, resource count, port forward count, errors)
- [x] Embedded terminal (PTY-based, inherits KUBECONFIG + context + namespace, Cmd+Shift+T)
- [x] Expanded quick actions per resource type:
  - Pods: port forward, debug container, evict
  - Deployments: restart, scale, rollback, rolling restart
  - StatefulSets/DaemonSets: restart, scale
  - CronJobs: trigger, suspend/resume
  - Nodes: cordon, uncordon, drain
  - Services: port forward
  - All resources: copy name, copy full name, delete
- [x] Additional resource types: Ingress, IngressClass, PV, PVC, NetworkPolicy, ServiceAccount, HPA, Namespace, Endpoints
- [x] Keyboard shortcuts (Cmd+1-9 resource types, Cmd+R refresh, Cmd+D detail, Cmd+Shift+T terminal)
- [ ] Performance: pagination for large resource lists (?limit=100&continue=)
- [ ] Performance: lazy loading in detail views
- [x] Connection failure banners per cluster (red banner with retry + dismiss)
- [ ] Auth token expiry detection and automatic re-auth
- [x] Empty states and loading states polish (namespace info, "Show All Namespaces" button)
- [x] Menu bar indicator for active port forwards (MenuBarExtra with stop controls)
- [x] App icon (real .icns with blue gradient K8s cube, visible in Dock)
- [x] About window (version, dependencies, badges)
- [x] CPU/RAM metrics (metrics-server integration, pod + node metrics, SwiftUI Charts)
- [x] Cluster overview dashboard (click cluster in sidebar: node status, resource summary, events, utilization)
- [x] Pod detail metrics (per-container CPU/memory bar charts)
- [x] Node detail metrics (usage vs capacity gauge bars)

---

## Dependencies
| Package | Version | Purpose |
|---------|---------|---------|
| [Yams](https://github.com/jpsim/Yams) | 5.1.3+ | YAML parsing for kubeconfig |

## Targets
- macOS 14+ (Sonoma)
- Swift 5.10+
- Apple Silicon + Intel (universal)
