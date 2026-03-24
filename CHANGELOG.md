# Changelog

All notable changes to OptaKube will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
