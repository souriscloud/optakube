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
                let status = viewModel.connectionStatuses[conn.id] ?? .disconnected
                HStack(spacing: 3) {
                    Circle()
                        .fill(customStore.color(for: conn.id))
                        .frame(width: 6, height: 6)
                    Text(customStore.displayName(for: conn))
                        .lineLimit(1)
                        .truncationMode(.middle)
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

            // Error
            if let error = viewModel.errorMessage {
                Divider().frame(height: 12)
                HStack(spacing: 3) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(error)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: 200)
                }
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
            default: break
            }
        }
        return "\(count) \(type.displayName.lowercased())"
    }
}
