import SwiftUI
import AppKit

struct StatusBar: View {
    @Environment(AppViewModel.self) private var viewModel
    @Binding var showTerminal: Bool
    var pfManager = PortForwardManager.shared
    var customStore = ClusterCustomizationStore.shared

    var body: some View {
        HStack(spacing: 10) {
            // Connection status with custom names/colors
            ForEach(viewModel.activeConnections) { conn in
                HStack(spacing: 3) {
                    Circle()
                        .fill(customStore.color(for: conn.id))
                        .frame(width: 6, height: 6)
                    Text(customStore.displayName(for: conn))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    // The dot above is the user's chosen cluster colour, not a health
                    // indicator — it looks like one, which is exactly why a frozen window
                    // read as healthy. Live updates get their own explicit badge.
                    watchBadge(for: conn.id)
                }
            }

            Divider().frame(height: 12)

            // Resource count
            if !viewModel.showClusterOverview {
                Text(resourceCountText)
            }

            // Active port forwards
            if !pfManager.activeForwards.isEmpty {
                Divider().frame(height: 12)
                HStack(spacing: 3) {
                    Image(systemName: "network")
                    Text("\(pfManager.activeForwards.filter(\.isRunning).count) fwd")
                }
                .foregroundStyle(.blue)
            }

            // Error. Dismissible, and the full text is available on hover — it used to be
            // a 200pt truncated line with no way to read the rest or clear it.
            if let error = viewModel.errorMessage {
                Divider().frame(height: 12)
                HStack(spacing: 3) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(error)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: 200)
                    Button {
                        viewModel.errorMessage = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Dismiss")
                }
                .help(error)
            }

            Spacer()

            // Last refresh time
            if let lastRefresh = viewModel.lastRefreshTime {
                Text(lastRefreshText(lastRefresh))
                    .foregroundStyle(.tertiary)
            }

            if viewModel.isLoading {
                ProgressView()
                    .controlSize(.mini)
            }

            Divider().frame(height: 12)

            // Support — Ko-fi (colored, clickable)
            Link(destination: AppInfo.kofiURL) {
                HStack(spacing: 3) {
                    Image(systemName: "cup.and.saucer.fill")
                    Text("Support")
                }
                .foregroundStyle(AppInfo.kofiColor)
            }
            .buttonStyle(.plain)
            .help("Support OptaKube on Ko-fi")

            Divider().frame(height: 12)

            // Version
            Text("v\(AppInfo.version)")
                .foregroundStyle(.tertiary)

            // Terminal toggle
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    showTerminal.toggle()
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "terminal")
                    if showTerminal {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8))
                    }
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Toggle embedded terminal (Cmd+Shift+T)")
            .keyboardShortcut("t", modifiers: [.command, .shift])
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(.bar)
    }

    /// Shows only when live updates are *not* healthy. A silent, always-present "live"
    /// badge would just become furniture; the useful signal is the exception.
    @ViewBuilder
    private func watchBadge(for clusterId: String) -> some View {
        switch viewModel.watchHealth[clusterId] {
        case .live, nil:
            EmptyView()
        case .reconnecting:
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.caption2)
                .foregroundStyle(.orange)
                .help("Live updates interrupted — reconnecting.")
        case .stale(let reason):
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(.orange)
                .help("Live updates stopped, polling instead. \(reason)")
        }
    }

    private func lastRefreshText(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 5 { return "just now" }
        if interval < 60 { return "\(Int(interval))s ago" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private var resourceCountText: String {
        let type = viewModel.selectedResourceType
        var count = 0
        for clusterId in viewModel.selectedClusterIds {
            switch type {
            case .pods: count += viewModel.pods[clusterId]?.count ?? 0
            case .deployments: count += viewModel.deployments[clusterId]?.count ?? 0
            case .services: count += viewModel.services[clusterId]?.count ?? 0
            case .nodes: count += viewModel.nodes[clusterId]?.count ?? 0
            case .statefulSets: count += viewModel.statefulSets[clusterId]?.count ?? 0
            case .daemonSets: count += viewModel.daemonSets[clusterId]?.count ?? 0
            case .replicaSets: count += viewModel.replicaSets[clusterId]?.count ?? 0
            case .jobs: count += viewModel.jobs[clusterId]?.count ?? 0
            case .cronJobs: count += viewModel.cronJobs[clusterId]?.count ?? 0
            case .configMaps: count += viewModel.configMaps[clusterId]?.count ?? 0
            case .secrets: count += viewModel.secrets[clusterId]?.count ?? 0
            // These 21 used to fall into `default: break`, so the footer read "0 ingresses"
            // with 47 of them on screen.
            case .ingresses: count += viewModel.ingresses[clusterId]?.count ?? 0
            case .ingressClasses: count += viewModel.ingressClasses[clusterId]?.count ?? 0
            case .persistentVolumes: count += viewModel.persistentVolumes[clusterId]?.count ?? 0
            case .persistentVolumeClaims: count += viewModel.persistentVolumeClaims[clusterId]?.count ?? 0
            case .networkPolicies: count += viewModel.networkPolicies[clusterId]?.count ?? 0
            case .serviceAccounts: count += viewModel.serviceAccounts[clusterId]?.count ?? 0
            case .horizontalPodAutoscalers: count += viewModel.horizontalPodAutoscalers[clusterId]?.count ?? 0
            case .namespaces: count += viewModel.namespaces[clusterId]?.count ?? 0
            case .endpoints: count += viewModel.endpoints[clusterId]?.count ?? 0
            case .roles: count += viewModel.roles[clusterId]?.count ?? 0
            case .roleBindings: count += viewModel.roleBindings[clusterId]?.count ?? 0
            case .clusterRoles: count += viewModel.clusterRoles[clusterId]?.count ?? 0
            case .clusterRoleBindings: count += viewModel.clusterRoleBindings[clusterId]?.count ?? 0
            case .storageClasses: count += viewModel.storageClasses[clusterId]?.count ?? 0
            case .resourceQuotas: count += viewModel.resourceQuotas[clusterId]?.count ?? 0
            case .podDisruptionBudgets: count += viewModel.podDisruptionBudgets[clusterId]?.count ?? 0
            case .limitRanges: count += viewModel.limitRanges[clusterId]?.count ?? 0
            case .priorityClasses: count += viewModel.priorityClasses[clusterId]?.count ?? 0
            case .leases: count += viewModel.leases[clusterId]?.count ?? 0
            case .mutatingWebhookConfigurations: count += viewModel.mutatingWebhookConfigurations[clusterId]?.count ?? 0
            case .validatingWebhookConfigurations: count += viewModel.validatingWebhookConfigurations[clusterId]?.count ?? 0
            }
        }
        return "\(count) \(type.displayName.lowercased())"
    }
}
