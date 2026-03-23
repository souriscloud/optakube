import SwiftUI
import AppKit

/// Context menu for right-clicking a resource row in any table
struct ResourceContextMenu: View {
    @Environment(AppViewModel.self) private var viewModel
    let resource: ResourceIdentifier

    var body: some View {
        // Workload actions
        if [.deployments, .statefulSets, .daemonSets].contains(resource.resourceType) {
            Button {
                Task {
                    guard let client = viewModel.activeClients[resource.clusterId] else { return }
                    try? await client.restart(resourceType: resource.resourceType, name: resource.name, namespace: resource.namespace)
                    await viewModel.refresh()
                }
            } label: {
                Label("Restart", systemImage: "arrow.clockwise")
            }
        }

        if [.deployments, .statefulSets, .replicaSets].contains(resource.resourceType) {
            Button {
                Task {
                    guard let client = viewModel.activeClients[resource.clusterId] else { return }
                    // Quick scale to 0 / scale up options
                    try? await client.scale(resourceType: resource.resourceType, name: resource.name, namespace: resource.namespace, replicas: 0)
                    await viewModel.refresh()
                }
            } label: {
                Label("Scale to 0", systemImage: "arrow.down.to.line")
            }
        }

        // CronJob actions
        if resource.resourceType == .cronJobs {
            Button {
                Task {
                    guard let client = viewModel.activeClients[resource.clusterId] else { return }
                    try? await client.triggerCronJob(name: resource.name, namespace: resource.namespace)
                    await viewModel.refresh()
                }
            } label: {
                Label("Trigger Job", systemImage: "bolt")
            }
        }

        // Node actions
        if resource.resourceType == .nodes {
            Button {
                Task {
                    guard let client = viewModel.activeClients[resource.clusterId] else { return }
                    let body = try? JSONSerialization.data(withJSONObject: ["spec": ["unschedulable": true]])
                    if let body { try? await client.patch(resourceType: .nodes, name: resource.name, namespace: nil, body: body) }
                    await viewModel.refresh()
                }
            } label: {
                Label("Cordon", systemImage: "nosign")
            }

            Button {
                Task {
                    guard let client = viewModel.activeClients[resource.clusterId] else { return }
                    let body = try? JSONSerialization.data(withJSONObject: ["spec": ["unschedulable": false]])
                    if let body { try? await client.patch(resourceType: .nodes, name: resource.name, namespace: nil, body: body) }
                    await viewModel.refresh()
                }
            } label: {
                Label("Uncordon", systemImage: "checkmark.circle")
            }
        }

        Divider()

        // Copy actions
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(resource.name, forType: .string)
        } label: {
            Label("Copy Name", systemImage: "doc.on.clipboard")
        }

        if let ns = resource.namespace {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("\(ns)/\(resource.name)", forType: .string)
            } label: {
                Label("Copy Full Name", systemImage: "doc.on.clipboard.fill")
            }
        }

        // Copy as kubectl command
        Button {
            let ns = resource.namespace.map { " -n \($0)" } ?? ""
            let cmd = "kubectl get \(resource.resourceType.resource) \(resource.name)\(ns)"
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(cmd, forType: .string)
        } label: {
            Label("Copy kubectl Command", systemImage: "terminal")
        }

        Divider()

        Button(role: .destructive) {
            Task {
                guard let client = viewModel.activeClients[resource.clusterId] else { return }
                try? await client.delete(resourceType: resource.resourceType, name: resource.name, namespace: resource.namespace)
                await viewModel.refresh()
            }
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
}
