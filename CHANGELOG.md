# Changelog

All notable changes to OptaKube will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
