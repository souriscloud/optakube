import SwiftUI
import AppKit

/// A mutating action requested from a context menu.
///
/// The menu can't present its own confirmation or alert: `.contextMenu`'s content isn't a
/// persistent view, so `.confirmationDialog` and `.alert` attached inside it never appear.
/// Actions are therefore posted to the enclosing list view, which owns the dialogs and
/// reports the outcome — the same indirection the existing `.openFullLogs` /
/// `.openPodExec` menu items already use.
struct ResourceActionRequest {
    enum Kind {
        case restart
        case scaleToZero
        case triggerJob
        case setCronJobSuspended(Bool)
        case setCordoned(Bool)
        case evict
        case delete

        /// Destructive or traffic-affecting actions get a confirmation first.
        var needsConfirmation: Bool {
            switch self {
            case .delete, .scaleToZero, .evict: return true
            case .restart, .triggerJob, .setCronJobSuspended, .setCordoned: return false
            }
        }
    }

    let resource: ResourceIdentifier
    let kind: Kind
}

extension Notification.Name {
    static let performResourceAction = Notification.Name("performResourceAction")
}

/// Context menu for right-clicking a resource row in any table
struct ResourceContextMenu: View {
    @Environment(AppViewModel.self) private var viewModel
    let resource: ResourceIdentifier

    private func request(_ kind: ResourceActionRequest.Kind) {
        NotificationCenter.default.post(
            name: .performResourceAction,
            object: ResourceActionRequest(resource: resource, kind: kind))
    }

    private var isCronJobSuspended: Bool {
        viewModel.cronJobs[resource.clusterId]?.first { $0.name == resource.name }?.isSuspended ?? false
    }

    private var isNodeCordoned: Bool {
        viewModel.nodes[resource.clusterId]?
            .first { $0.name == resource.name }?.spec?.unschedulable ?? false
    }

    var body: some View {
        // Pod-specific: open full-window logs and exec
        if resource.resourceType == .pods {
            Button {
                NotificationCenter.default.post(name: .openFullLogs, object: resource)
            } label: {
                Label("Open Logs", systemImage: "doc.text")
            }
            Button {
                NotificationCenter.default.post(name: .openPodExec, object: resource)
            } label: {
                Label("Exec Shell", systemImage: "terminal")
            }
            Divider()
        }

        // Workload actions
        if [.deployments, .statefulSets, .daemonSets].contains(resource.resourceType) {
            Button { request(.restart) } label: {
                Label("Restart", systemImage: "arrow.clockwise")
            }
        }

        if [.deployments, .statefulSets, .replicaSets].contains(resource.resourceType) {
            Button { request(.scaleToZero) } label: {
                Label("Scale to 0", systemImage: "arrow.down.to.line")
            }
        }

        // CronJob actions
        if resource.resourceType == .cronJobs {
            Button { request(.triggerJob) } label: {
                Label("Trigger Job", systemImage: "bolt")
            }
            let suspended = isCronJobSuspended
            Button { request(.setCronJobSuspended(!suspended)) } label: {
                Label(suspended ? "Resume" : "Suspend",
                      systemImage: suspended ? "play" : "pause")
            }
        }

        // Pod eviction — honours PodDisruptionBudgets, unlike a plain delete.
        if resource.resourceType == .pods {
            Button { request(.evict) } label: {
                Label("Evict", systemImage: "arrow.uturn.right")
            }
        }

        // Node actions
        if resource.resourceType == .nodes {
            let cordoned = isNodeCordoned
            Button { request(.setCordoned(!cordoned)) } label: {
                Label(cordoned ? "Uncordon" : "Cordon",
                      systemImage: cordoned ? "checkmark.circle" : "nosign")
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

        Button(role: .destructive) { request(.delete) } label: {
            Label("Delete", systemImage: "trash")
        }
    }
}
