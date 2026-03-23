import SwiftUI
import AppKit

struct StatusBar: View {
    @Environment(AppViewModel.self) private var viewModel
    @Binding var showTerminal: Bool
    var pfManager = PortForwardManager.shared

    var body: some View {
        HStack(spacing: 10) {
            // Connection status
            ForEach(viewModel.activeConnections) { conn in
                let status = viewModel.connectionStatuses[conn.id] ?? .disconnected
                HStack(spacing: 3) {
                    Circle()
                        .fill(statusColor(status))
                        .frame(width: 6, height: 6)
                    Text(conn.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Divider().frame(height: 12)

            // Resource count
            Text(resourceCountText)

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

            if viewModel.isLoading {
                ProgressView()
                    .controlSize(.mini)
            }

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

    private func statusColor(_ status: ConnectionStatus) -> Color {
        switch status {
        case .disconnected: return .gray
        case .connecting: return .orange
        case .connected: return .green
        case .error: return .red
        }
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
