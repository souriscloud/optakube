# OptaKube

A free, native macOS Kubernetes GUI client. Built with Swift and SwiftUI.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)
![Swift 5.10](https://img.shields.io/badge/Swift-5.10-orange)
![License](https://img.shields.io/badge/License-MIT-green)

## Features

- **Multi-cluster** — one window per cluster, independent state
- **20+ built-in resource types** — Pods, Deployments, Services, Nodes, StatefulSets, DaemonSets, ReplicaSets, Jobs, CronJobs, ConfigMaps, Secrets, Ingresses, PVs, PVCs, NetworkPolicies, ServiceAccounts, HPAs, Namespaces, Endpoints, IngressClasses
- **CRD support** — auto-discovers and browses any Custom Resource Definition
- **CPU/Memory metrics** — inline usage bars in tables, per-container charts, node utilization
- **Cluster overview dashboard** — node status, resource summary, events, utilization gauges
- **Live updates** — Watch API for real-time resource changes
- **Log streaming** — multi-pod aggregation, search, timestamps, export
- **Embedded terminal** — real PTY with full shell support, inherits kubeconfig
- **YAML editor** — syntax highlighting, edit and apply changes
- **Quick actions** — restart, scale, rollback, port forward, debug containers, cordon/drain nodes
- **Spotlight search** (Cmd+K) — search across all resources, namespaces, types, CRDs
- **Auth support** — kubeconfig tokens, client certificates (EC + RSA), exec-based (AWS EKS, etc.)
- **Auto-updates** — via Sparkle framework

## Install

Download the latest release from the [Releases](https://github.com/souriscloud/optakube/releases) page.

Or build from source:
```bash
git clone https://github.com/souriscloud/optakube.git
cd optakube
swift build -c release
open .build/release/OptaKube
```

## Requirements

- macOS 14 (Sonoma) or later
- `kubectl` on PATH (for port forwarding)

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| Cmd+K | Spotlight search |
| Cmd+D | Toggle detail panel |
| Cmd+R | Refresh |
| Cmd+Shift+T | Toggle terminal |
| Cmd+1-9 | Switch resource type |

## Architecture

- **SwiftUI** + **@Observable** for reactive UI
- **URLSession** for K8s API (no third-party HTTP libs)
- **Security.framework** + **openssl** for TLS client certificates
- **SwiftTerm** for embedded terminal
- **Yams** for YAML parsing
- **SwiftUI Charts** for metrics visualization
- **Sparkle** for auto-updates

## Made by

[Souris.CLOUD](https://bio.souris.cloud)

If you find OptaKube useful, consider [supporting on Ko-fi](https://ko-fi.com/souriscloud).

## License

MIT
