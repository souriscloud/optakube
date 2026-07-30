import SwiftUI

struct ResourceListView: View {
    @Environment(AppViewModel.self) private var viewModel
    @Binding var selectedResource: ResourceIdentifier?
    /// Custom-resource instance currently open in the YAML editor sheet.
    @State private var crdEditItem: GenericK8sResource?
    @State private var crdDeleteItem: GenericK8sResource?
    @State private var crdSelection: GenericK8sResource.ID?
    /// Multi-row selection. Drives the inspector when exactly one row is selected, and
    /// the bulk-action bar when two or more are.
    @State private var multiSelection = Set<ResourceIdentifier>()
    @State private var showBulkDeleteConfirm = false
    @State private var bulkOutcome: BulkOutcome?
    @State private var pendingAction: ResourceActionRequest?

    struct BulkOutcome: Identifiable {
        let id = UUID()
        let message: String
        let isError: Bool
    }

    var body: some View {
        @Bindable var viewModel = viewModel
        return Group {
            if let crd = viewModel.selectedCRD {
                // CRD custom resource view
                crdResourceView(crd: crd)
            } else if viewModel.isLoading && allItems.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Loading \(viewModel.selectedResourceType.displayName)...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let ns = viewModel.selectedNamespace {
                        Text("Namespace: \(ns)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if allItems.isEmpty, let failure = loadFailure {
                // Distinguishing "nothing here" from "we couldn't look" matters most on
                // Secrets and RBAC types: a 403 used to render the friendly empty state,
                // so users concluded the namespace was empty.
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 36))
                        .foregroundStyle(.orange)
                    Text("Couldn't list \(viewModel.selectedResourceType.displayName)")
                        .font(.title3)
                        .fontWeight(.medium)
                    Text(failure)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .textSelection(.enabled)
                        .frame(maxWidth: 420)
                    Button("Retry") { Task { await viewModel.refresh() } }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if allItems.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: viewModel.selectedResourceType.systemImage)
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("No \(viewModel.selectedResourceType.displayName)")
                        .font(.title3)
                        .fontWeight(.medium)
                    // Only namespaced types can be filtered by namespace. Offering "Show
                    // All Namespaces" for StorageClasses or ClusterRoles was misleading:
                    // the namespace was never in the request, so the button changed nothing.
                    if viewModel.selectedResourceType.isNamespaced,
                       let ns = viewModel.selectedNamespace {
                        Text("No resources found in namespace \"\(ns)\"")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button("Show All Namespaces") {
                            viewModel.selectedNamespace = nil
                            Task { await viewModel.refresh() }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    } else if viewModel.selectedResourceType.isNamespaced {
                        Text("No resources found across all namespaces")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("This cluster has no \(viewModel.selectedResourceType.displayName.lowercased())")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                switch viewModel.selectedResourceType {
                case .pods: podTable
                case .deployments: deploymentTable
                case .services: serviceTable
                case .nodes: nodeTable
                case .statefulSets: statefulSetTable
                case .daemonSets: daemonSetTable
                case .replicaSets: replicaSetTable
                case .jobs: jobTable
                case .cronJobs: cronJobTable
                case .configMaps: configMapTable
                case .secrets: secretTable
                case .ingresses: ingressTable
                case .ingressClasses: ingressClassTable
                case .persistentVolumes: persistentVolumeTable
                case .persistentVolumeClaims: persistentVolumeClaimTable
                case .networkPolicies: networkPolicyTable
                case .serviceAccounts: serviceAccountTable
                case .horizontalPodAutoscalers: hpaTable
                case .namespaces: namespaceTable
                case .endpoints: endpointsTable
                case .roles: roleTable
                case .roleBindings: roleBindingTable
                case .clusterRoles: clusterRoleTable
                case .clusterRoleBindings: clusterRoleBindingTable
                case .storageClasses: storageClassTable
                case .resourceQuotas: resourceQuotaTable
                case .podDisruptionBudgets: podDisruptionBudgetTable
                case .limitRanges: limitRangeTable
                case .priorityClasses: priorityClassTable
                case .leases: leaseTable
                case .mutatingWebhookConfigurations: mutatingWebhookTable
                case .validatingWebhookConfigurations: validatingWebhookTable
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle(viewModel.selectedCRD?.displayName ?? viewModel.selectedResourceType.displayName)
        .safeAreaInset(edge: .top) {
            if viewModel.selectedCRD == nil, !allItems.isEmpty || viewModel.isLoading || !viewModel.labelFilter.isEmpty {
                HStack(spacing: 8) {
                    Circle()
                        .fill(.green)
                        .frame(width: 7, height: 7)
                    Text("\(allItems.count) \(allItems.count == 1 ? "resource" : "resources")")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let ns = viewModel.selectedNamespace {
                        Text(ns)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .foregroundStyle(Color.accentColor)
                    } else {
                        Text("All Namespaces")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    labelFilterField(filter: $viewModel.labelFilter)
                    pinButton

                    if viewModel.isLoading {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 4)
                .background(.bar)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if multiSelection.count >= 2 { bulkActionBar }
        }
        // Keep the single-selection inspector in sync: it shows only when exactly one
        // row is selected; 0 or 2+ selected clears it.
        .onChange(of: multiSelection) { _, sel in
            selectedResource = sel.count == 1 ? sel.first : nil
        }
        // Reflect an externally-driven selection (e.g. Spotlight navigation) back into
        // the table's selection set, without bouncing the onChange above.
        .onChange(of: selectedResource) { _, rid in
            if let rid {
                if multiSelection != [rid] { multiSelection = [rid] }
            } else if multiSelection.count == 1 {
                multiSelection.removeAll()
            }
        }
        .confirmationDialog(bulkDeletePrompt, isPresented: $showBulkDeleteConfirm, titleVisibility: .visible) {
            Button("Delete \(multiSelection.count)", role: .destructive) { bulkDelete() }
            Button("Cancel", role: .cancel) {}
        }
        // Right-click actions are posted here rather than performed in the menu, which
        // can't host its own dialogs. Previously they ran immediately with a bare `try?`:
        // Delete had no confirmation at all (while the same Delete in the inspector did),
        // and a mis-click on "Scale to 0" took a Deployment out of production silently.
        .task {
            for await request in Self.actionRequests() {
                if request.kind.needsConfirmation {
                    pendingAction = request
                } else {
                    await perform(request)
                }
            }
        }
        .confirmationDialog(confirmationTitle,
                            isPresented: Binding(get: { pendingAction != nil },
                                                 set: { if !$0 { pendingAction = nil } }),
                            titleVisibility: .visible,
                            presenting: pendingAction) { request in
            Button(confirmationVerb(for: request.kind), role: .destructive) {
                let captured = request
                pendingAction = nil
                Task { await perform(captured) }
            }
            Button("Cancel", role: .cancel) { pendingAction = nil }
        } message: { request in
            Text(confirmationMessage(for: request.kind))
        }
        .alert(bulkOutcome?.isError == true ? "Some resources were not changed" : "Done",
               isPresented: Binding(get: { bulkOutcome != nil },
                                    set: { if !$0 { bulkOutcome = nil } }),
               presenting: bulkOutcome) { outcome in
            if outcome.isError {
                Button("Copy details") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(outcome.message, forType: .string)
                    bulkOutcome = nil
                }
            }
            Button("OK", role: .cancel) { bulkOutcome = nil }
        } message: { outcome in
            Text(outcome.message)
        }
    }

    // MARK: - Bulk Actions

    /// Selected types that support `kubectl rollout restart`.
    private var restartableSelection: [ResourceIdentifier] {
        multiSelection.filter { [.deployments, .statefulSets, .daemonSets].contains($0.resourceType) }
    }

    private var bulkDeletePrompt: String {
        "Delete \(multiSelection.count) selected resource\(multiSelection.count == 1 ? "" : "s")?"
    }

    private var bulkActionBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "checklist").foregroundStyle(.tint)
            Text("\(multiSelection.count) selected").font(.callout.weight(.medium))
            Spacer()
            if !restartableSelection.isEmpty {
                Button {
                    bulkRestart()
                } label: {
                    Label("Restart \(restartableSelection.count)", systemImage: "arrow.clockwise")
                }
            }
            Button(role: .destructive) {
                showBulkDeleteConfirm = true
            } label: {
                Label("Delete \(multiSelection.count)", systemImage: "trash")
            }
            .tint(.red)
            Button("Clear") { multiSelection.removeAll() }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: - Single-resource actions from the context menu

    /// Context-menu action requests, unwrapped to a Sendable value.
    ///
    /// `Notification` isn't `Sendable`, so awaiting one directly in a `@MainActor` view body
    /// crosses an actor boundary with a non-Sendable value — a warning today and an error
    /// under Swift 6. Unwrapping inside a nonisolated task keeps the Notification there.
    private static func actionRequests() -> AsyncStream<ResourceActionRequest> {
        AsyncStream { continuation in
            let task = Task.detached {
                let stream = NotificationCenter.default.notifications(named: .performResourceAction)
                for await note in stream {
                    if let request = note.object as? ResourceActionRequest {
                        continuation.yield(request)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private var confirmationTitle: String {
        guard let request = pendingAction else { return "" }
        switch request.kind {
        case .delete: return "Delete \(request.resource.name)?"
        case .scaleToZero: return "Scale \(request.resource.name) to zero?"
        case .evict: return "Evict \(request.resource.name)?"
        default: return request.resource.name
        }
    }

    private func confirmationVerb(for kind: ResourceActionRequest.Kind) -> String {
        switch kind {
        case .delete: return "Delete"
        case .scaleToZero: return "Scale to 0"
        case .evict: return "Evict"
        default: return "Continue"
        }
    }

    private func confirmationMessage(for kind: ResourceActionRequest.Kind) -> String {
        switch kind {
        case .delete:
            return "This action cannot be undone."
        case .scaleToZero:
            return "Every replica is removed, so this stops serving traffic until it's scaled back up."
        case .evict:
            return "The pod is deleted, subject to any PodDisruptionBudget. Its controller decides whether to replace it."
        default:
            return ""
        }
    }

    private func perform(_ request: ResourceActionRequest) async {
        let rid = request.resource
        guard let client = viewModel.activeClients[rid.clusterId] else {
            bulkOutcome = BulkOutcome(message: "Not connected to \(rid.name)'s cluster.", isError: true)
            return
        }

        let succeeded: String
        do {
            switch request.kind {
            case .restart:
                try await client.restart(resourceType: rid.resourceType, name: rid.name,
                                         namespace: rid.namespace)
                succeeded = "Restarted \(rid.name)."
            case .scaleToZero:
                try await client.scale(resourceType: rid.resourceType, name: rid.name,
                                       namespace: rid.namespace, replicas: 0)
                succeeded = "Scaled \(rid.name) to 0."
            case .triggerJob:
                try await client.triggerCronJob(name: rid.name, namespace: rid.namespace)
                succeeded = "Triggered a job from \(rid.name)."
            case .setCronJobSuspended(let suspend):
                try await client.suspendCronJob(name: rid.name, namespace: rid.namespace,
                                                suspend: suspend)
                succeeded = "\(suspend ? "Suspended" : "Resumed") \(rid.name)."
            case .setCordoned(let cordon):
                let body = try JSONSerialization.data(
                    withJSONObject: ["spec": ["unschedulable": cordon]])
                try await client.patch(resourceType: .nodes, name: rid.name,
                                       namespace: nil, body: body)
                succeeded = "\(cordon ? "Cordoned" : "Uncordoned") \(rid.name)."
            case .evict:
                guard let ns = rid.namespace else {
                    bulkOutcome = BulkOutcome(message: "\(rid.name) has no namespace, so it cannot be evicted.",
                                              isError: true)
                    return
                }
                try await client.evict(podName: rid.name, namespace: ns)
                succeeded = "Evicted \(rid.name)."
            case .delete:
                try await client.delete(resourceType: rid.resourceType, name: rid.name,
                                        namespace: rid.namespace)
                succeeded = "Deleted \(rid.name)."
            }
            bulkOutcome = BulkOutcome(message: succeeded, isError: false)
        } catch {
            bulkOutcome = BulkOutcome(message: error.localizedDescription, isError: true)
        }
        await viewModel.refresh()
    }

    private func deleteCustomResource(_ item: GenericK8sResource, crd: CRDDefinition) async {
        let cid = clusterId(forCRDItem: item)
        guard let client = viewModel.activeClients[cid] else {
            bulkOutcome = BulkOutcome(message: "Not connected to this cluster.", isError: true)
            return
        }
        do {
            try await client.deleteCustomResource(
                crd: crd, name: item.name,
                namespace: item.namespace.isEmpty ? nil : item.namespace)
            bulkOutcome = BulkOutcome(message: "Deleted \(item.name).", isError: false)
        } catch {
            bulkOutcome = BulkOutcome(message: error.localizedDescription, isError: true)
        }
        await viewModel.refresh()
    }

    private func bulkDelete() {
        runBulk(Array(multiSelection), verb: "Deleted") { client, rid in
            try await client.delete(resourceType: rid.resourceType, name: rid.name,
                                    namespace: rid.namespace)
        }
    }

    private func bulkRestart() {
        runBulk(restartableSelection, verb: "Restarted") { client, rid in
            try await client.restart(resourceType: rid.resourceType, name: rid.name,
                                     namespace: rid.namespace)
        }
    }

    /// Applies an operation across a selection and reports what actually happened.
    /// Previously each item was a bare `try?`, so selecting 20 rows and confirming Delete
    /// cleared the selection and brought 17 rows back — blocked by a PodDisruptionBudget,
    /// RBAC or finalizers — with no explanation anywhere.
    private func runBulk(_ targets: [ResourceIdentifier], verb: String,
                        _ body: @escaping (K8sAPIClient, ResourceIdentifier) async throws -> Void) {
        Task {
            var succeeded = 0
            var failures: [String] = []
            for rid in targets {
                guard let client = viewModel.activeClients[rid.clusterId] else {
                    failures.append("\(rid.name): not connected to its cluster")
                    continue
                }
                do {
                    try await body(client, rid)
                    succeeded += 1
                } catch {
                    failures.append("\(rid.name): \(error.localizedDescription)")
                }
            }
            await MainActor.run {
                multiSelection.removeAll()
                if failures.isEmpty {
                    bulkOutcome = BulkOutcome(
                        message: "\(verb) \(succeeded) resource\(succeeded == 1 ? "" : "s").",
                        isError: false)
                } else {
                    bulkOutcome = BulkOutcome(
                        message: "\(verb) \(succeeded) of \(targets.count).\n\n"
                            + failures.prefix(10).joined(separator: "\n")
                            + (failures.count > 10 ? "\n… and \(failures.count - 10) more." : ""),
                        isError: true)
                }
            }
            await viewModel.refresh()
        }
    }

    // MARK: - Label Filter + Pin

    @ViewBuilder
    private func labelFilterField(filter: Binding<String>) -> some View {
        let value = filter.wrappedValue
        let valid = value.isEmpty || LabelFilter(value).isValid
        HStack(spacing: 4) {
            Image(systemName: "tag")
                .font(.caption2)
                .foregroundStyle(valid ? Color.secondary : Color.red)
            TextField("label=value", text: filter)
                .textFieldStyle(.plain)
                .font(.caption)
                .frame(width: 180)
            if !value.isEmpty {
                Button {
                    filter.wrappedValue = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(valid ? Color.clear : Color.red.opacity(0.6), lineWidth: 1)
        )
        .help("Filter by Kubernetes label selector, e.g. app=web,tier!=db")
    }

    private var pinButton: some View {
        let store = SavedViewsStore.shared
        let existing = store.existing(
            namespace: viewModel.selectedNamespace,
            resourceType: viewModel.selectedResourceType.rawValue,
            labelFilter: viewModel.labelFilter
        )
        return Button {
            if let existing {
                store.remove(existing.id)
            } else {
                store.add(SavedView(
                    name: savedViewName,
                    namespace: viewModel.selectedNamespace,
                    resourceType: viewModel.selectedResourceType.rawValue,
                    labelFilter: viewModel.labelFilter
                ))
            }
        } label: {
            Image(systemName: existing != nil ? "star.fill" : "star")
                .font(.caption)
                .foregroundStyle(existing != nil ? Color.yellow : Color.secondary)
        }
        .buttonStyle(.plain)
        .help(existing != nil ? "Unpin this view" : "Pin this view to Favorites")
    }

    /// A readable default name for a pinned view: "ns · Type" plus the filter if set.
    private var savedViewName: String {
        let ns = viewModel.selectedNamespace ?? "all-ns"
        var name = "\(ns) · \(viewModel.selectedResourceType.displayName)"
        if !viewModel.labelFilter.isEmpty {
            name += " (\(viewModel.labelFilter))"
        }
        return name
    }

    // MARK: - Pod Table

    private var podTable: some View {
        Table(filteredRows(from: \.pods, type: .pods) { PodRow(id: $0, pod: $1, clusterId: $2) }, selection: $multiSelection) {
            TableColumn("") { item in ResourceStatusBadge(status: item.pod.resourceStatus) }.width(24)
            TableColumn("Name") { item in
                Text(item.pod.name).fontWeight(.medium).foregroundStyle(Color(red: 0.29, green: 0.62, blue: 1.0))
                    .contextMenu { ResourceContextMenu(resource: item.id) }
            }.width(min: 150, ideal: 250)
            TableColumn("Namespace", value: \.pod.namespace).width(min: 80, ideal: 120)
            TableColumn("Ready") { item in Text("\(item.pod.readyCount)/\(item.pod.totalContainers)").monospacedDigit() }.width(50)
            TableColumn("CPU") { item in
                MiniUsageBar(
                    value: podCPU(item.pod.name, ns: item.pod.namespace, clusterId: item.clusterId),
                    label: podCPULabel(item.pod.name, ns: item.pod.namespace, clusterId: item.clusterId),
                    color: .blue
                )
            }.width(80)
            TableColumn("Memory") { item in
                MiniUsageBar(
                    value: podMemory(item.pod.name, ns: item.pod.namespace, clusterId: item.clusterId),
                    label: podMemoryLabel(item.pod.name, ns: item.pod.namespace, clusterId: item.clusterId),
                    color: .purple
                )
            }.width(80)
            TableColumn("Restarts") { item in
                Text("\(item.pod.restartCount)").monospacedDigit()
                    .foregroundStyle(item.pod.restartCount > 0 ? .orange : .primary)
            }.width(55)
            TableColumn("Age") { item in Text(item.pod.age).foregroundStyle(.secondary) }.width(50)
            TableColumn("Node", value: \.pod.nodeName).width(min: 80, ideal: 120)
        }
    }

    // MARK: - Deployment Table

    private var deploymentTable: some View {
        Table(filteredRows(from: \.deployments, type: .deployments) { DeploymentRow(id: $0, deployment: $1, clusterId: $2) }, selection: $multiSelection) {
            TableColumn("") { item in ResourceStatusBadge(status: item.deployment.resourceStatus) }.width(24)
            TableColumn("Name") { item in Text(item.deployment.name).fontWeight(.medium).foregroundStyle(Color(red: 0.29, green: 0.62, blue: 1.0)).contextMenu { ResourceContextMenu(resource: item.id) } }.width(min: 150, ideal: 250)
            TableColumn("Namespace", value: \.deployment.namespace).width(min: 80, ideal: 120)
            TableColumn("Ready") { item in Text("\(item.deployment.readyReplicas)/\(item.deployment.replicas)").monospacedDigit() }.width(60)
            TableColumn("Up-to-date") { item in Text("\(item.deployment.updatedReplicas)").monospacedDigit() }.width(70)
            TableColumn("Available") { item in Text("\(item.deployment.availableReplicas)").monospacedDigit() }.width(65)
            TableColumn("Age") { item in Text(item.deployment.age).foregroundStyle(.secondary) }.width(50)
        }
    }

    // MARK: - Service Table

    private var serviceTable: some View {
        Table(filteredRows(from: \.services, type: .services) { ServiceRow(id: $0, service: $1, clusterId: $2) }, selection: $multiSelection) {
            TableColumn("") { item in ResourceStatusBadge(status: item.service.resourceStatus) }.width(24)
            TableColumn("Name") { item in Text(item.service.name).fontWeight(.medium).foregroundStyle(Color(red: 0.29, green: 0.62, blue: 1.0)).contextMenu { ResourceContextMenu(resource: item.id) } }.width(min: 150, ideal: 250)
            TableColumn("Namespace", value: \.service.namespace).width(min: 80, ideal: 120)
            TableColumn("Type", value: \.service.serviceType).width(80)
            TableColumn("Cluster IP", value: \.service.clusterIP).width(min: 100, ideal: 130)
            TableColumn("Ports") { item in Text(item.service.portsDisplay).font(.caption) }.width(min: 100, ideal: 200)
            TableColumn("Age") { item in Text(item.service.age).foregroundStyle(.secondary) }.width(50)
        }
    }

    // MARK: - Node Table

    private var nodeTable: some View {
        Table(filteredRows(from: \.nodes, type: .nodes, namespaced: false) { NodeRow(id: $0, node: $1, clusterId: $2) }, selection: $multiSelection) {
            TableColumn("") { item in ResourceStatusBadge(status: item.node.resourceStatus) }.width(24)
            TableColumn("Name") { item in Text(item.node.name).fontWeight(.medium).foregroundStyle(Color(red: 0.29, green: 0.62, blue: 1.0)).contextMenu { ResourceContextMenu(resource: item.id) } }.width(min: 150, ideal: 250)
            TableColumn("Roles") { item in Text(item.node.roles) }.width(min: 80, ideal: 100)
            TableColumn("CPU") { item in
                MiniUsageBar(
                    value: nodeCPUPercent(item.node, clusterId: item.clusterId),
                    label: nodeCPULabel(item.node, clusterId: item.clusterId),
                    color: .blue
                )
            }.width(90)
            TableColumn("Memory") { item in
                MiniUsageBar(
                    value: nodeMemPercent(item.node, clusterId: item.clusterId),
                    label: nodeMemLabel(item.node, clusterId: item.clusterId),
                    color: .purple
                )
            }.width(90)
            TableColumn("Version", value: \.node.kubeletVersion).width(min: 60, ideal: 90)
            TableColumn("Age") { item in Text(item.node.age).foregroundStyle(.secondary) }.width(50)
        }
    }

    // MARK: - StatefulSet Table

    private var statefulSetTable: some View {
        Table(filteredRows(from: \.statefulSets, type: .statefulSets) { StatefulSetRow(id: $0, statefulSet: $1, clusterId: $2) }, selection: $multiSelection) {
            TableColumn("") { item in ResourceStatusBadge(status: item.statefulSet.resourceStatus) }.width(24)
            TableColumn("Name") { item in Text(item.statefulSet.name).fontWeight(.medium).foregroundStyle(Color(red: 0.29, green: 0.62, blue: 1.0)).contextMenu { ResourceContextMenu(resource: item.id) } }.width(min: 150, ideal: 250)
            TableColumn("Namespace", value: \.statefulSet.namespace).width(min: 80, ideal: 120)
            TableColumn("Ready") { item in Text("\(item.statefulSet.readyReplicas)/\(item.statefulSet.replicas)").monospacedDigit() }.width(60)
            TableColumn("Age") { item in Text(item.statefulSet.age).foregroundStyle(.secondary) }.width(50)
        }
    }

    // MARK: - DaemonSet Table

    private var daemonSetTable: some View {
        Table(filteredRows(from: \.daemonSets, type: .daemonSets) { DaemonSetRow(id: $0, daemonSet: $1, clusterId: $2) }, selection: $multiSelection) {
            TableColumn("") { item in ResourceStatusBadge(status: item.daemonSet.resourceStatus) }.width(24)
            TableColumn("Name") { item in Text(item.daemonSet.name).fontWeight(.medium).foregroundStyle(Color(red: 0.29, green: 0.62, blue: 1.0)).contextMenu { ResourceContextMenu(resource: item.id) } }.width(min: 150, ideal: 250)
            TableColumn("Namespace", value: \.daemonSet.namespace).width(min: 80, ideal: 120)
            TableColumn("Desired") { item in Text("\(item.daemonSet.desiredNumberScheduled)").monospacedDigit() }.width(55)
            TableColumn("Ready") { item in Text("\(item.daemonSet.numberReady)").monospacedDigit() }.width(50)
            TableColumn("Age") { item in Text(item.daemonSet.age).foregroundStyle(.secondary) }.width(50)
        }
    }

    // MARK: - ReplicaSet Table

    private var replicaSetTable: some View {
        Table(filteredRows(from: \.replicaSets, type: .replicaSets) { ReplicaSetRow(id: $0, replicaSet: $1, clusterId: $2) }, selection: $multiSelection) {
            TableColumn("") { item in ResourceStatusBadge(status: item.replicaSet.resourceStatus) }.width(24)
            TableColumn("Name") { item in Text(item.replicaSet.name).fontWeight(.medium).foregroundStyle(Color(red: 0.29, green: 0.62, blue: 1.0)).contextMenu { ResourceContextMenu(resource: item.id) } }.width(min: 150, ideal: 250)
            TableColumn("Namespace", value: \.replicaSet.namespace).width(min: 80, ideal: 120)
            TableColumn("Ready") { item in Text("\(item.replicaSet.readyReplicas)/\(item.replicaSet.replicas)").monospacedDigit() }.width(60)
            TableColumn("Age") { item in Text(item.replicaSet.age).foregroundStyle(.secondary) }.width(50)
        }
    }

    // MARK: - Job Table

    private var jobTable: some View {
        Table(filteredRows(from: \.jobs, type: .jobs) { JobRow(id: $0, job: $1, clusterId: $2) }, selection: $multiSelection) {
            TableColumn("") { item in ResourceStatusBadge(status: item.job.resourceStatus) }.width(24)
            TableColumn("Name") { item in Text(item.job.name).fontWeight(.medium).foregroundStyle(Color(red: 0.29, green: 0.62, blue: 1.0)).contextMenu { ResourceContextMenu(resource: item.id) } }.width(min: 150, ideal: 250)
            TableColumn("Namespace", value: \.job.namespace).width(min: 80, ideal: 120)
            TableColumn("Completions") { item in Text("\(item.job.succeeded)/\(item.job.completions)").monospacedDigit() }.width(80)
            TableColumn("Duration") { item in Text(item.job.duration).foregroundStyle(.secondary) }.width(70)
            TableColumn("Age") { item in Text(item.job.age).foregroundStyle(.secondary) }.width(50)
        }
    }

    // MARK: - CronJob Table

    private var cronJobTable: some View {
        Table(filteredRows(from: \.cronJobs, type: .cronJobs) { CronJobRow(id: $0, cronJob: $1, clusterId: $2) }, selection: $multiSelection) {
            TableColumn("") { item in ResourceStatusBadge(status: item.cronJob.resourceStatus) }.width(24)
            TableColumn("Name") { item in Text(item.cronJob.name).fontWeight(.medium).foregroundStyle(Color(red: 0.29, green: 0.62, blue: 1.0)).contextMenu { ResourceContextMenu(resource: item.id) } }.width(min: 150, ideal: 250)
            TableColumn("Namespace", value: \.cronJob.namespace).width(min: 80, ideal: 120)
            TableColumn("Schedule", value: \.cronJob.schedule).width(min: 80, ideal: 120)
            TableColumn("Suspended") { item in
                Image(systemName: item.cronJob.isSuspended ? "pause.circle.fill" : "play.circle.fill")
                    .foregroundStyle(item.cronJob.isSuspended ? .orange : .green)
            }.width(65)
            TableColumn("Last Run") { item in Text(item.cronJob.lastScheduleDisplay).foregroundStyle(.secondary) }.width(80)
            TableColumn("Age") { item in Text(item.cronJob.age).foregroundStyle(.secondary) }.width(50)
        }
    }

    // MARK: - ConfigMap Table

    private var configMapTable: some View {
        Table(filteredRows(from: \.configMaps, type: .configMaps) { ConfigMapRow(id: $0, configMap: $1, clusterId: $2) }, selection: $multiSelection) {
            TableColumn("") { _ in ResourceStatusBadge(status: .running) }.width(24)
            TableColumn("Name") { item in Text(item.configMap.name).fontWeight(.medium).foregroundStyle(Color(red: 0.29, green: 0.62, blue: 1.0)).contextMenu { ResourceContextMenu(resource: item.id) } }.width(min: 150, ideal: 250)
            TableColumn("Namespace", value: \.configMap.namespace).width(min: 80, ideal: 120)
            TableColumn("Data") { item in Text("\(item.configMap.dataCount) keys").monospacedDigit() }.width(70)
            TableColumn("Age") { item in Text(item.configMap.age).foregroundStyle(.secondary) }.width(50)
        }
    }

    // MARK: - Secret Table

    private var secretTable: some View {
        Table(filteredRows(from: \.secrets, type: .secrets) { SecretRow(id: $0, secret: $1, clusterId: $2) }, selection: $multiSelection) {
            TableColumn("") { _ in ResourceStatusBadge(status: .running) }.width(24)
            TableColumn("Name") { item in Text(item.secret.name).fontWeight(.medium).foregroundStyle(Color(red: 0.29, green: 0.62, blue: 1.0)).contextMenu { ResourceContextMenu(resource: item.id) } }.width(min: 150, ideal: 250)
            TableColumn("Namespace", value: \.secret.namespace).width(min: 80, ideal: 120)
            TableColumn("Type", value: \.secret.secretType).width(min: 100, ideal: 150)
            TableColumn("Data") { item in Text("\(item.secret.dataCount) keys").monospacedDigit() }.width(70)
            TableColumn("Age") { item in Text(item.secret.age).foregroundStyle(.secondary) }.width(50)
        }
    }

    // MARK: - Ingress Table

    private var ingressTable: some View {
        Table(filteredRows(from: \.ingresses, type: .ingresses) { IngressRow(id: $0, ingress: $1, clusterId: $2) }, selection: $multiSelection) {
            TableColumn("") { item in ResourceStatusBadge(status: item.ingress.resourceStatus) }.width(24)
            TableColumn("Name") { item in Text(item.ingress.name).fontWeight(.medium).foregroundStyle(Color(red: 0.29, green: 0.62, blue: 1.0)).contextMenu { ResourceContextMenu(resource: item.id) } }.width(min: 150, ideal: 250)
            TableColumn("Namespace", value: \.ingress.namespace).width(min: 80, ideal: 120)
            TableColumn("Hosts") { item in Text(item.ingress.hostsDisplay).font(.caption) }.width(min: 100, ideal: 200)
            TableColumn("Paths") { item in Text(item.ingress.pathsDisplay).font(.caption) }.width(min: 80, ideal: 150)
            TableColumn("Backend") { item in Text(item.ingress.backendServiceDisplay).font(.caption) }.width(min: 80, ideal: 150)
            TableColumn("TLS") { item in
                Image(systemName: item.ingress.tlsEnabled ? "lock.fill" : "lock.open")
                    .foregroundStyle(item.ingress.tlsEnabled ? .green : .secondary)
            }.width(35)
            TableColumn("Age") { item in Text(item.ingress.age).foregroundStyle(.secondary) }.width(50)
        }
    }

    // MARK: - IngressClass Table

    private var ingressClassTable: some View {
        Table(filteredRows(from: \.ingressClasses, type: .ingressClasses, namespaced: false) { IngressClassRow(id: $0, ingressClass: $1, clusterId: $2) }, selection: $multiSelection) {
            TableColumn("") { item in ResourceStatusBadge(status: item.ingressClass.resourceStatus) }.width(24)
            TableColumn("Name") { item in Text(item.ingressClass.name).fontWeight(.medium).foregroundStyle(Color(red: 0.29, green: 0.62, blue: 1.0)).contextMenu { ResourceContextMenu(resource: item.id) } }.width(min: 150, ideal: 250)
            TableColumn("Controller", value: \.ingressClass.controller).width(min: 150, ideal: 250)
            TableColumn("Default") { item in
                Image(systemName: item.ingressClass.isDefault ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.ingressClass.isDefault ? .green : .secondary)
            }.width(55)
            TableColumn("Age") { item in Text(item.ingressClass.age).foregroundStyle(.secondary) }.width(50)
        }
    }

    // MARK: - PersistentVolume Table

    private var persistentVolumeTable: some View {
        Table(filteredRows(from: \.persistentVolumes, type: .persistentVolumes, namespaced: false) { PersistentVolumeRow(id: $0, persistentVolume: $1, clusterId: $2) }, selection: $multiSelection) {
            TableColumn("") { item in ResourceStatusBadge(status: item.persistentVolume.resourceStatus) }.width(24)
            TableColumn("Name") { item in Text(item.persistentVolume.name).fontWeight(.medium).foregroundStyle(Color(red: 0.29, green: 0.62, blue: 1.0)).contextMenu { ResourceContextMenu(resource: item.id) } }.width(min: 150, ideal: 250)
            TableColumn("Capacity", value: \.persistentVolume.capacity).width(70)
            TableColumn("Access Modes") { item in Text(item.persistentVolume.accessModesDisplay).font(.caption) }.width(min: 80, ideal: 150)
            TableColumn("Reclaim Policy", value: \.persistentVolume.reclaimPolicy).width(100)
            TableColumn("Status", value: \.persistentVolume.phase).width(70)
            TableColumn("Storage Class", value: \.persistentVolume.storageClassName).width(min: 80, ideal: 120)
            TableColumn("Age") { item in Text(item.persistentVolume.age).foregroundStyle(.secondary) }.width(50)
        }
    }

    // MARK: - PersistentVolumeClaim Table

    private var persistentVolumeClaimTable: some View {
        Table(filteredRows(from: \.persistentVolumeClaims, type: .persistentVolumeClaims) { PersistentVolumeClaimRow(id: $0, persistentVolumeClaim: $1, clusterId: $2) }, selection: $multiSelection) {
            TableColumn("") { item in ResourceStatusBadge(status: item.persistentVolumeClaim.resourceStatus) }.width(24)
            TableColumn("Name") { item in Text(item.persistentVolumeClaim.name).fontWeight(.medium).foregroundStyle(Color(red: 0.29, green: 0.62, blue: 1.0)).contextMenu { ResourceContextMenu(resource: item.id) } }.width(min: 150, ideal: 250)
            TableColumn("Namespace", value: \.persistentVolumeClaim.namespace).width(min: 80, ideal: 120)
            TableColumn("Status", value: \.persistentVolumeClaim.phase).width(70)
            TableColumn("Volume", value: \.persistentVolumeClaim.volumeName).width(min: 80, ideal: 150)
            TableColumn("Capacity", value: \.persistentVolumeClaim.capacity).width(70)
            TableColumn("Access Modes") { item in Text(item.persistentVolumeClaim.accessModesDisplay).font(.caption) }.width(min: 80, ideal: 120)
            TableColumn("Storage Class", value: \.persistentVolumeClaim.storageClassName).width(min: 80, ideal: 120)
            TableColumn("Age") { item in Text(item.persistentVolumeClaim.age).foregroundStyle(.secondary) }.width(50)
        }
    }

    // MARK: - NetworkPolicy Table

    private var networkPolicyTable: some View {
        Table(filteredRows(from: \.networkPolicies, type: .networkPolicies) { NetworkPolicyRow(id: $0, networkPolicy: $1, clusterId: $2) }, selection: $multiSelection) {
            TableColumn("") { item in ResourceStatusBadge(status: item.networkPolicy.resourceStatus) }.width(24)
            TableColumn("Name") { item in Text(item.networkPolicy.name).fontWeight(.medium).foregroundStyle(Color(red: 0.29, green: 0.62, blue: 1.0)).contextMenu { ResourceContextMenu(resource: item.id) } }.width(min: 150, ideal: 250)
            TableColumn("Namespace", value: \.networkPolicy.namespace).width(min: 80, ideal: 120)
            TableColumn("Pod Selector") { item in Text(item.networkPolicy.podSelectorDisplay).font(.caption) }.width(min: 100, ideal: 200)
            TableColumn("Policy Types") { item in Text(item.networkPolicy.policyTypesDisplay) }.width(min: 80, ideal: 120)
            TableColumn("Age") { item in Text(item.networkPolicy.age).foregroundStyle(.secondary) }.width(50)
        }
    }

    // MARK: - ServiceAccount Table

    private var serviceAccountTable: some View {
        Table(filteredRows(from: \.serviceAccounts, type: .serviceAccounts) { ServiceAccountRow(id: $0, serviceAccount: $1, clusterId: $2) }, selection: $multiSelection) {
            TableColumn("") { _ in ResourceStatusBadge(status: .running) }.width(24)
            TableColumn("Name") { item in Text(item.serviceAccount.name).fontWeight(.medium).foregroundStyle(Color(red: 0.29, green: 0.62, blue: 1.0)).contextMenu { ResourceContextMenu(resource: item.id) } }.width(min: 150, ideal: 250)
            TableColumn("Namespace", value: \.serviceAccount.namespace).width(min: 80, ideal: 120)
            TableColumn("Secrets") { item in Text("\(item.serviceAccount.secretsCount)").monospacedDigit() }.width(55)
            TableColumn("Age") { item in Text(item.serviceAccount.age).foregroundStyle(.secondary) }.width(50)
        }
    }

    // MARK: - HorizontalPodAutoscaler Table

    private var hpaTable: some View {
        Table(filteredRows(from: \.horizontalPodAutoscalers, type: .horizontalPodAutoscalers) { HPARow(id: $0, hpa: $1, clusterId: $2) }, selection: $multiSelection) {
            TableColumn("") { item in ResourceStatusBadge(status: item.hpa.resourceStatus) }.width(24)
            TableColumn("Name") { item in Text(item.hpa.name).fontWeight(.medium).foregroundStyle(Color(red: 0.29, green: 0.62, blue: 1.0)).contextMenu { ResourceContextMenu(resource: item.id) } }.width(min: 150, ideal: 250)
            TableColumn("Namespace", value: \.hpa.namespace).width(min: 80, ideal: 120)
            TableColumn("Min") { item in Text("\(item.hpa.minReplicas)").monospacedDigit() }.width(35)
            TableColumn("Max") { item in Text("\(item.hpa.maxReplicas)").monospacedDigit() }.width(35)
            TableColumn("Replicas") { item in Text("\(item.hpa.currentReplicas)/\(item.hpa.desiredReplicas)").monospacedDigit() }.width(65)
            TableColumn("Current") { item in Text(item.hpa.currentMetricsDisplay).font(.caption) }.width(min: 80, ideal: 150)
            TableColumn("Target") { item in Text(item.hpa.targetMetricsDisplay).font(.caption) }.width(min: 80, ideal: 150)
            TableColumn("Age") { item in Text(item.hpa.age).foregroundStyle(.secondary) }.width(50)
        }
    }

    // MARK: - Namespace Table

    private var namespaceTable: some View {
        Table(filteredRows(from: \.namespaces, type: .namespaces, namespaced: false) { NamespaceRow(id: $0, ns: $1, clusterId: $2) }, selection: $multiSelection) {
            TableColumn("") { item in ResourceStatusBadge(status: item.ns.resourceStatus) }.width(24)
            TableColumn("Name") { item in Text(item.ns.name).fontWeight(.medium).foregroundStyle(Color(red: 0.29, green: 0.62, blue: 1.0)).contextMenu { ResourceContextMenu(resource: item.id) } }.width(min: 150, ideal: 250)
            TableColumn("Status", value: \.ns.phase).width(80)
            TableColumn("Age") { item in Text(item.ns.age).foregroundStyle(.secondary) }.width(50)
        }
    }

    // MARK: - Endpoints Table

    private var endpointsTable: some View {
        Table(filteredRows(from: \.endpoints, type: .endpoints) { EndpointsRow(id: $0, endpoints: $1, clusterId: $2) }, selection: $multiSelection) {
            TableColumn("") { item in ResourceStatusBadge(status: item.endpoints.resourceStatus) }.width(24)
            TableColumn("Name") { item in Text(item.endpoints.name).fontWeight(.medium).foregroundStyle(Color(red: 0.29, green: 0.62, blue: 1.0)).contextMenu { ResourceContextMenu(resource: item.id) } }.width(min: 150, ideal: 250)
            TableColumn("Namespace", value: \.endpoints.namespace).width(min: 80, ideal: 120)
            TableColumn("Addresses") { item in Text("\(item.endpoints.addressCount)").monospacedDigit() }.width(65)
            TableColumn("Ports") { item in Text(item.endpoints.portsDisplay).font(.caption) }.width(min: 100, ideal: 200)
            TableColumn("Age") { item in Text(item.endpoints.age).foregroundStyle(.secondary) }.width(50)
        }
    }

    // MARK: - Role Table

    private var roleTable: some View {
        Table(filteredRows(from: \.roles, type: .roles) { RoleRow(id: $0, role: $1, clusterId: $2) }, selection: $multiSelection) {
            TableColumn("") { _ in ResourceStatusBadge(status: .running) }.width(24)
            TableColumn("Name") { item in Text(item.role.name).fontWeight(.medium).foregroundStyle(Color(red: 0.29, green: 0.62, blue: 1.0)).contextMenu { ResourceContextMenu(resource: item.id) } }.width(min: 150, ideal: 250)
            TableColumn("Namespace", value: \.role.namespace).width(min: 80, ideal: 120)
            TableColumn("Rules") { item in Text("\(item.role.rulesCount)").monospacedDigit() }.width(45)
            TableColumn("Verbs") { item in Text(item.role.verbsSummary).font(.caption).foregroundStyle(.secondary) }.width(min: 100, ideal: 220)
            TableColumn("Age") { item in Text(item.role.age).foregroundStyle(.secondary) }.width(50)
        }
    }

    // MARK: - RoleBinding Table

    private var roleBindingTable: some View {
        Table(filteredRows(from: \.roleBindings, type: .roleBindings) { RoleBindingRow(id: $0, roleBinding: $1, clusterId: $2) }, selection: $multiSelection) {
            TableColumn("") { _ in ResourceStatusBadge(status: .running) }.width(24)
            TableColumn("Name") { item in Text(item.roleBinding.name).fontWeight(.medium).foregroundStyle(Color(red: 0.29, green: 0.62, blue: 1.0)).contextMenu { ResourceContextMenu(resource: item.id) } }.width(min: 150, ideal: 220)
            TableColumn("Namespace", value: \.roleBinding.namespace).width(min: 80, ideal: 120)
            TableColumn("Role") { item in Text(item.roleBinding.roleRefDisplay).font(.caption) }.width(min: 100, ideal: 180)
            TableColumn("Subjects") { item in Text(item.roleBinding.subjectsDisplay).font(.caption).foregroundStyle(.secondary) }.width(min: 100, ideal: 220)
            TableColumn("Age") { item in Text(item.roleBinding.age).foregroundStyle(.secondary) }.width(50)
        }
    }

    // MARK: - ClusterRole Table

    private var clusterRoleTable: some View {
        Table(filteredRows(from: \.clusterRoles, type: .clusterRoles, namespaced: false) { ClusterRoleRow(id: $0, clusterRole: $1, clusterId: $2) }, selection: $multiSelection) {
            TableColumn("") { _ in ResourceStatusBadge(status: .running) }.width(24)
            TableColumn("Name") { item in Text(item.clusterRole.name).fontWeight(.medium).foregroundStyle(Color(red: 0.29, green: 0.62, blue: 1.0)).contextMenu { ResourceContextMenu(resource: item.id) } }.width(min: 150, ideal: 300)
            TableColumn("Rules") { item in Text("\(item.clusterRole.rulesCount)").monospacedDigit() }.width(45)
            TableColumn("Verbs") { item in Text(item.clusterRole.verbsSummary).font(.caption).foregroundStyle(.secondary) }.width(min: 120, ideal: 260)
            TableColumn("Age") { item in Text(item.clusterRole.age).foregroundStyle(.secondary) }.width(50)
        }
    }

    // MARK: - ClusterRoleBinding Table

    private var clusterRoleBindingTable: some View {
        Table(filteredRows(from: \.clusterRoleBindings, type: .clusterRoleBindings, namespaced: false) { ClusterRoleBindingRow(id: $0, clusterRoleBinding: $1, clusterId: $2) }, selection: $multiSelection) {
            TableColumn("") { _ in ResourceStatusBadge(status: .running) }.width(24)
            TableColumn("Name") { item in Text(item.clusterRoleBinding.name).fontWeight(.medium).foregroundStyle(Color(red: 0.29, green: 0.62, blue: 1.0)).contextMenu { ResourceContextMenu(resource: item.id) } }.width(min: 150, ideal: 260)
            TableColumn("Role") { item in Text(item.clusterRoleBinding.roleRefDisplay).font(.caption) }.width(min: 100, ideal: 200)
            TableColumn("Subjects") { item in Text(item.clusterRoleBinding.subjectsDisplay).font(.caption).foregroundStyle(.secondary) }.width(min: 120, ideal: 260)
            TableColumn("Age") { item in Text(item.clusterRoleBinding.age).foregroundStyle(.secondary) }.width(50)
        }
    }

    // MARK: - StorageClass Table

    private var storageClassTable: some View {
        Table(filteredRows(from: \.storageClasses, type: .storageClasses, namespaced: false) { StorageClassRow(id: $0, storageClass: $1, clusterId: $2) }, selection: $multiSelection) {
            TableColumn("") { _ in ResourceStatusBadge(status: .running) }.width(24)
            TableColumn("Name") { item in
                HStack(spacing: 4) {
                    Text(item.storageClass.name).fontWeight(.medium).foregroundStyle(Color(red: 0.29, green: 0.62, blue: 1.0))
                    if item.storageClass.isDefault {
                        Text("default").font(.system(size: 9)).padding(.horizontal, 4).padding(.vertical, 1).background(.green.opacity(0.2)).foregroundStyle(.green).clipShape(Capsule())
                    }
                }
                .contextMenu { ResourceContextMenu(resource: item.id) }
            }.width(min: 150, ideal: 220)
            TableColumn("Provisioner") { item in Text(item.storageClass.provisioner ?? "—").font(.caption) }.width(min: 120, ideal: 220)
            TableColumn("Reclaim") { item in Text(item.storageClass.reclaimPolicyDisplay).font(.caption) }.width(80)
            TableColumn("Binding") { item in Text(item.storageClass.bindingModeDisplay).font(.caption) }.width(min: 90, ideal: 120)
            TableColumn("Age") { item in Text(item.storageClass.age).foregroundStyle(.secondary) }.width(50)
        }
    }

    // MARK: - ResourceQuota Table

    private var resourceQuotaTable: some View {
        Table(filteredRows(from: \.resourceQuotas, type: .resourceQuotas) { ResourceQuotaRow(id: $0, resourceQuota: $1, clusterId: $2) }, selection: $multiSelection) {
            TableColumn("") { _ in ResourceStatusBadge(status: .running) }.width(24)
            TableColumn("Name") { item in Text(item.resourceQuota.name).fontWeight(.medium).foregroundStyle(Color(red: 0.29, green: 0.62, blue: 1.0)).contextMenu { ResourceContextMenu(resource: item.id) } }.width(min: 120, ideal: 180)
            TableColumn("Namespace", value: \.resourceQuota.namespace).width(min: 80, ideal: 120)
            TableColumn("Used") { item in Text(item.resourceQuota.usedDisplay).font(.caption).foregroundStyle(.secondary) }.width(min: 100, ideal: 200)
            TableColumn("Hard") { item in Text(item.resourceQuota.hardDisplay).font(.caption) }.width(min: 100, ideal: 200)
            TableColumn("Age") { item in Text(item.resourceQuota.age).foregroundStyle(.secondary) }.width(50)
        }
    }

    // MARK: - PodDisruptionBudget Table

    private var podDisruptionBudgetTable: some View {
        Table(filteredRows(from: \.podDisruptionBudgets, type: .podDisruptionBudgets) { PodDisruptionBudgetRow(id: $0, podDisruptionBudget: $1, clusterId: $2) }, selection: $multiSelection) {
            TableColumn("") { item in ResourceStatusBadge(status: item.podDisruptionBudget.resourceStatus) }.width(24)
            TableColumn("Name") { item in Text(item.podDisruptionBudget.name).fontWeight(.medium).foregroundStyle(Color(red: 0.29, green: 0.62, blue: 1.0)).contextMenu { ResourceContextMenu(resource: item.id) } }.width(min: 130, ideal: 200)
            TableColumn("Namespace", value: \.podDisruptionBudget.namespace).width(min: 80, ideal: 120)
            TableColumn("Min Avail") { item in Text(item.podDisruptionBudget.minAvailableDisplay).font(.caption).monospacedDigit() }.width(70)
            TableColumn("Max Unavail") { item in Text(item.podDisruptionBudget.maxUnavailableDisplay).font(.caption).monospacedDigit() }.width(85)
            TableColumn("Allowed") { item in Text("\(item.podDisruptionBudget.allowedDisruptions)").monospacedDigit() }.width(60)
            TableColumn("Healthy") { item in Text(item.podDisruptionBudget.healthyDisplay).monospacedDigit() }.width(60)
            TableColumn("Age") { item in Text(item.podDisruptionBudget.age).foregroundStyle(.secondary) }.width(50)
        }
    }

    // MARK: - LimitRange Table

    private var limitRangeTable: some View {
        Table(filteredRows(from: \.limitRanges, type: .limitRanges) { LimitRangeRow(id: $0, limitRange: $1, clusterId: $2) }, selection: $multiSelection) {
            TableColumn("") { _ in ResourceStatusBadge(status: .running) }.width(24)
            TableColumn("Name") { item in Text(item.limitRange.name).fontWeight(.medium).foregroundStyle(Color(red: 0.29, green: 0.62, blue: 1.0)).contextMenu { ResourceContextMenu(resource: item.id) } }.width(min: 150, ideal: 250)
            TableColumn("Namespace", value: \.limitRange.namespace).width(min: 80, ideal: 120)
            TableColumn("Types") { item in Text(item.limitRange.limitTypes).font(.caption) }.width(min: 100, ideal: 200)
            TableColumn("Age") { item in Text(item.limitRange.age).foregroundStyle(.secondary) }.width(50)
        }
    }

    // MARK: - PriorityClass Table

    private var priorityClassTable: some View {
        Table(filteredRows(from: \.priorityClasses, type: .priorityClasses, namespaced: false) { PriorityClassRow(id: $0, priorityClass: $1, clusterId: $2) }, selection: $multiSelection) {
            TableColumn("") { _ in ResourceStatusBadge(status: .running) }.width(24)
            TableColumn("Name") { item in
                HStack(spacing: 4) {
                    Text(item.priorityClass.name).fontWeight(.medium).foregroundStyle(Color(red: 0.29, green: 0.62, blue: 1.0))
                    if item.priorityClass.isGlobalDefault {
                        Text("default").font(.system(size: 9)).padding(.horizontal, 4).padding(.vertical, 1).background(.green.opacity(0.2)).foregroundStyle(.green).clipShape(Capsule())
                    }
                }
                .contextMenu { ResourceContextMenu(resource: item.id) }
            }.width(min: 150, ideal: 250)
            TableColumn("Value") { item in Text(item.priorityClass.valueDisplay).monospacedDigit() }.width(90)
            TableColumn("Age") { item in Text(item.priorityClass.age).foregroundStyle(.secondary) }.width(50)
        }
    }

    // MARK: - Lease Table

    private var leaseTable: some View {
        Table(filteredRows(from: \.leases, type: .leases) { LeaseRow(id: $0, lease: $1, clusterId: $2) }, selection: $multiSelection) {
            TableColumn("") { _ in ResourceStatusBadge(status: .running) }.width(24)
            TableColumn("Name") { item in Text(item.lease.name).fontWeight(.medium).foregroundStyle(Color(red: 0.29, green: 0.62, blue: 1.0)).contextMenu { ResourceContextMenu(resource: item.id) } }.width(min: 150, ideal: 250)
            TableColumn("Namespace", value: \.lease.namespace).width(min: 80, ideal: 120)
            TableColumn("Holder") { item in Text(item.lease.holder).font(.caption).lineLimit(1).truncationMode(.middle) }.width(min: 120, ideal: 240)
            TableColumn("Duration") { item in Text(item.lease.durationDisplay).font(.caption).monospacedDigit() }.width(70)
            TableColumn("Age") { item in Text(item.lease.age).foregroundStyle(.secondary) }.width(50)
        }
    }

    // MARK: - MutatingWebhookConfiguration Table

    private var mutatingWebhookTable: some View {
        Table(filteredRows(from: \.mutatingWebhookConfigurations, type: .mutatingWebhookConfigurations, namespaced: false) { MutatingWebhookRow(id: $0, config: $1, clusterId: $2) }, selection: $multiSelection) {
            TableColumn("") { _ in ResourceStatusBadge(status: .running) }.width(24)
            TableColumn("Name") { item in Text(item.config.name).fontWeight(.medium).foregroundStyle(Color(red: 0.29, green: 0.62, blue: 1.0)).contextMenu { ResourceContextMenu(resource: item.id) } }.width(min: 180, ideal: 320)
            TableColumn("Webhooks") { item in Text("\(item.config.webhookCount)").monospacedDigit() }.width(70)
            TableColumn("Age") { item in Text(item.config.age).foregroundStyle(.secondary) }.width(50)
        }
    }

    // MARK: - ValidatingWebhookConfiguration Table

    private var validatingWebhookTable: some View {
        Table(filteredRows(from: \.validatingWebhookConfigurations, type: .validatingWebhookConfigurations, namespaced: false) { ValidatingWebhookRow(id: $0, config: $1, clusterId: $2) }, selection: $multiSelection) {
            TableColumn("") { _ in ResourceStatusBadge(status: .running) }.width(24)
            TableColumn("Name") { item in Text(item.config.name).fontWeight(.medium).foregroundStyle(Color(red: 0.29, green: 0.62, blue: 1.0)).contextMenu { ResourceContextMenu(resource: item.id) } }.width(min: 180, ideal: 320)
            TableColumn("Webhooks") { item in Text("\(item.config.webhookCount)").monospacedDigit() }.width(70)
            TableColumn("Age") { item in Text(item.config.age).foregroundStyle(.secondary) }.width(50)
        }
    }

    // MARK: - Generic Row Builder

    private func filteredRows<T: K8sResource, Row: Identifiable>(
        from keyPath: KeyPath<AppViewModel, [String: [T]]>,
        type: ResourceType,
        namespaced: Bool = true,
        build: (ResourceIdentifier, T, String) -> Row
    ) -> [Row] where Row.ID == ResourceIdentifier {
        let selector = LabelFilter(viewModel.labelFilter)
        var rows: [Row] = []
        for clusterId in viewModel.selectedClusterIds {
            for item in viewModel[keyPath: keyPath][clusterId] ?? [] {
                guard selector.matches(item.metadata.labels) else { continue }
                let rid = ResourceIdentifier(
                    clusterId: clusterId,
                    resourceType: type,
                    name: item.name,
                    namespace: namespaced ? item.metadata.namespace : nil
                )
                rows.append(build(rid, item, clusterId))
            }
        }
        if !viewModel.searchText.isEmpty {
            rows = rows.filter { row in
                if let rid = (row as? any ResourceRow)?.resourceId {
                    return rid.name.localizedCaseInsensitiveContains(viewModel.searchText)
                }
                return true
            }
        }
        return rows
    }

    /// The reason the most recent list attempt failed, if any of the selected clusters
    /// reported one. Used to replace the empty state with an error state.
    private var loadFailure: String? {
        for clusterId in viewModel.selectedClusterIds {
            if let message = viewModel.resourceLoadErrors[clusterId] { return message }
        }
        return nil
    }

    private var allItems: [ResourceIdentifier] {
        let selector = LabelFilter(viewModel.labelFilter)
        var items: [ResourceIdentifier] = []
        for clusterId in viewModel.selectedClusterIds {
            let type = viewModel.selectedResourceType
            func add<T: K8sResource>(_ kp: KeyPath<AppViewModel, [String: [T]]>, namespaced: Bool = true) {
                items += (viewModel[keyPath: kp][clusterId] ?? [])
                    .filter { selector.matches($0.metadata.labels) }
                    .map {
                        ResourceIdentifier(clusterId: clusterId, resourceType: type, name: $0.name, namespace: namespaced ? $0.metadata.namespace : nil)
                    }
            }
            switch type {
            case .pods: add(\.pods)
            case .deployments: add(\.deployments)
            case .services: add(\.services)
            case .nodes: add(\.nodes, namespaced: false)
            case .statefulSets: add(\.statefulSets)
            case .daemonSets: add(\.daemonSets)
            case .replicaSets: add(\.replicaSets)
            case .jobs: add(\.jobs)
            case .cronJobs: add(\.cronJobs)
            case .configMaps: add(\.configMaps)
            case .secrets: add(\.secrets)
            case .ingresses: add(\.ingresses)
            case .ingressClasses: add(\.ingressClasses, namespaced: false)
            case .persistentVolumes: add(\.persistentVolumes, namespaced: false)
            case .persistentVolumeClaims: add(\.persistentVolumeClaims)
            case .networkPolicies: add(\.networkPolicies)
            case .serviceAccounts: add(\.serviceAccounts)
            case .horizontalPodAutoscalers: add(\.horizontalPodAutoscalers)
            case .namespaces: add(\.namespaces, namespaced: false)
            case .endpoints: add(\.endpoints)
            case .roles: add(\.roles)
            case .roleBindings: add(\.roleBindings)
            case .clusterRoles: add(\.clusterRoles, namespaced: false)
            case .clusterRoleBindings: add(\.clusterRoleBindings, namespaced: false)
            case .storageClasses: add(\.storageClasses, namespaced: false)
            case .resourceQuotas: add(\.resourceQuotas)
            case .podDisruptionBudgets: add(\.podDisruptionBudgets)
            case .limitRanges: add(\.limitRanges)
            case .priorityClasses: add(\.priorityClasses, namespaced: false)
            case .leases: add(\.leases)
            case .mutatingWebhookConfigurations: add(\.mutatingWebhookConfigurations, namespaced: false)
            case .validatingWebhookConfigurations: add(\.validatingWebhookConfigurations, namespaced: false)
            }
        }
        if !viewModel.searchText.isEmpty {
            items = items.filter { $0.name.localizedCaseInsensitiveContains(viewModel.searchText) }
        }
        return items
    }

    private func clusterName(for clusterId: String) -> String {
        viewModel.availableConnections.first { $0.id == clusterId }?.name ?? clusterId
    }

    // MARK: - CRD Resource View

    @ViewBuilder
    private func crdResourceView(crd: CRDDefinition) -> some View {
        let allCrdItems = viewModel.selectedClusterIds.flatMap { viewModel.customResources[$0] ?? [] }
        let filtered = viewModel.searchText.isEmpty ? allCrdItems : allCrdItems.filter {
            $0.name.localizedCaseInsensitiveContains(viewModel.searchText)
        }

        if viewModel.isLoading && filtered.isEmpty {
            ProgressView("Loading \(crd.displayName)...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filtered.isEmpty {
            ContentUnavailableView(
                "No \(crd.displayName)",
                systemImage: "puzzlepiece.extension",
                description: Text("No custom resources found")
            )
        } else {
            // The table had no `selection:` and no `primaryAction:`, so clicking a custom
            // resource did nothing and double-clicking did nothing — the only route in was
            // right-clicking the Name cell specifically, whose menu had two items.
            Table(filtered, selection: $crdSelection) {
                TableColumn("Name") { item in
                    Text(item.name)
                        .fontWeight(.medium)
                        .foregroundStyle(Color(red: 0.29, green: 0.62, blue: 1.0))
                }
                .width(min: 150, ideal: 250)

                TableColumn("Namespace", value: \.namespace)
                    .width(min: 80, ideal: 120)

                TableColumn("Status") { item in
                    let phase = item.statusPhase
                    Text(phase.isEmpty ? "-" : phase)
                        .foregroundStyle(phase == "Ready" || phase == "Active" || phase == "Running" ? .green : .secondary)
                }
                .width(80)

                TableColumn("Age") { item in
                    Text(item.age)
                        .foregroundStyle(.secondary)
                }
                .width(50)

                TableColumn("API") { _ in
                    Text("\(crd.group)/\(crd.version)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .width(min: 100, ideal: 150)
            }
            .contextMenu(forSelectionType: GenericK8sResource.ID.self) { ids in
                if let id = ids.first, let item = filtered.first(where: { $0.id == id }) {
                    Button {
                        crdEditItem = item
                    } label: {
                        Label("Edit YAML…", systemImage: "pencil")
                    }
                    Divider()
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(item.name, forType: .string)
                    } label: {
                        Label("Copy Name", systemImage: "doc.on.clipboard")
                    }
                    Button {
                        let ns = item.namespace.isEmpty ? "" : " -n \(item.namespace)"
                        let cmd = "kubectl get \(crd.plural).\(crd.group) \(item.name)\(ns)"
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(cmd, forType: .string)
                    } label: {
                        Label("Copy kubectl Command", systemImage: "terminal")
                    }
                    Divider()
                    Button(role: .destructive) {
                        crdDeleteItem = item
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            } primaryAction: { ids in
                if let id = ids.first, let item = filtered.first(where: { $0.id == id }) {
                    crdEditItem = item
                }
            }
            .confirmationDialog("Delete \(crdDeleteItem?.name ?? "")?",
                                isPresented: Binding(get: { crdDeleteItem != nil },
                                                     set: { if !$0 { crdDeleteItem = nil } }),
                                titleVisibility: .visible,
                                presenting: crdDeleteItem) { item in
                Button("Delete", role: .destructive) {
                    let target = item
                    crdDeleteItem = nil
                    Task { await deleteCustomResource(target, crd: crd) }
                }
                Button("Cancel", role: .cancel) { crdDeleteItem = nil }
            } message: { _ in
                Text("This action cannot be undone.")
            }
            .sheet(item: $crdEditItem) { item in
                CRDInstanceDetailView(
                    crd: crd,
                    item: item,
                    clusterId: clusterId(forCRDItem: item),
                    onChanged: { Task { await viewModel.refresh() } }
                )
                .environment(viewModel)
            }
        }
    }

    /// Best-effort owning cluster for a custom-resource instance (its id is
    /// namespace/name; cross-cluster name collisions are rare and fall back to the
    /// first selected cluster).
    private func clusterId(forCRDItem item: GenericK8sResource) -> String {
        for cid in viewModel.selectedClusterIds where (viewModel.customResources[cid] ?? []).contains(where: { $0.id == item.id }) {
            return cid
        }
        return viewModel.selectedClusterIds.first ?? ""
    }

    // MARK: - Pod Metrics Helpers

    private func podMetrics(_ name: String, ns: String, clusterId: String) -> PodMetrics? {
        viewModel.podMetricsCache[clusterId]?.first { $0.name == name && $0.namespace == ns }
    }

    private func podCPU(_ name: String, ns: String, clusterId: String) -> Double? {
        guard let m = podMetrics(name, ns: ns, clusterId: clusterId) else { return nil }
        // Try to compute percentage from requests
        let used = m.totalCPU
        if let pod = viewModel.pods[clusterId]?.first(where: { $0.name == name }),
           let containers = pod.spec?.containers {
            let requested = containers.compactMap { $0.resources?.requests?["cpu"] }.reduce(0.0) { $0 + K8sQuantity.parseCPU($1) }
            if requested > 0 { return min(used / requested, 2.0) }
        }
        return nil // No percentage without requests, just show label
    }

    private func podCPULabel(_ name: String, ns: String, clusterId: String) -> String {
        guard let m = podMetrics(name, ns: ns, clusterId: clusterId) else { return "-" }
        let used = K8sQuantity.formatCPU(m.totalCPU)
        if let pod = viewModel.pods[clusterId]?.first(where: { $0.name == name }),
           let containers = pod.spec?.containers {
            let req = containers.compactMap { $0.resources?.requests?["cpu"] }.reduce(0.0) { $0 + K8sQuantity.parseCPU($1) }
            let lim = containers.compactMap { $0.resources?.limits?["cpu"] }.reduce(0.0) { $0 + K8sQuantity.parseCPU($1) }
            if lim > 0 { return "\(used)/\(K8sQuantity.formatCPU(lim))" }
            if req > 0 { return "\(used)/\(K8sQuantity.formatCPU(req))" }
        }
        return used
    }

    private func podMemory(_ name: String, ns: String, clusterId: String) -> Double? {
        guard let m = podMetrics(name, ns: ns, clusterId: clusterId) else { return nil }
        let used = m.totalMemory
        if let pod = viewModel.pods[clusterId]?.first(where: { $0.name == name }),
           let containers = pod.spec?.containers {
            let requested = containers.compactMap { $0.resources?.requests?["memory"] }.reduce(0.0) { $0 + K8sQuantity.parseMemory($1) }
            if requested > 0 { return min(used / requested, 2.0) }
            let limited = containers.compactMap { $0.resources?.limits?["memory"] }.reduce(0.0) { $0 + K8sQuantity.parseMemory($1) }
            if limited > 0 { return min(used / limited, 2.0) }
        }
        return nil
    }

    private func podMemoryLabel(_ name: String, ns: String, clusterId: String) -> String {
        guard let m = podMetrics(name, ns: ns, clusterId: clusterId) else { return "-" }
        let used = K8sQuantity.formatMemory(m.totalMemory)
        if let pod = viewModel.pods[clusterId]?.first(where: { $0.name == name }),
           let containers = pod.spec?.containers {
            let lim = containers.compactMap { $0.resources?.limits?["memory"] }.reduce(0.0) { $0 + K8sQuantity.parseMemory($1) }
            let req = containers.compactMap { $0.resources?.requests?["memory"] }.reduce(0.0) { $0 + K8sQuantity.parseMemory($1) }
            if lim > 0 { return "\(used)/\(K8sQuantity.formatMemory(lim))" }
            if req > 0 { return "\(used)/\(K8sQuantity.formatMemory(req))" }
        }
        return used
    }

    // MARK: - Node Metrics Helpers

    private func nodeMetrics(_ node: Node, clusterId: String) -> NodeMetrics? {
        viewModel.nodeMetricsCache[clusterId]?.first { $0.name == node.name }
    }

    private func nodeCPUPercent(_ node: Node, clusterId: String) -> Double? {
        guard let m = nodeMetrics(node, clusterId: clusterId),
              let capStr = node.status?.capacity?["cpu"] else { return nil }
        let capacity = K8sQuantity.parseCPU(capStr)
        guard capacity > 0 else { return nil }
        return m.cpuCores / capacity
    }

    private func nodeCPULabel(_ node: Node, clusterId: String) -> String {
        guard let m = nodeMetrics(node, clusterId: clusterId) else { return "-" }
        let capStr = node.status?.capacity?["cpu"] ?? ""
        let cap = K8sQuantity.parseCPU(capStr)
        if cap > 0 {
            return "\(K8sQuantity.formatCPU(m.cpuCores))/\(K8sQuantity.formatCPU(cap))"
        }
        return K8sQuantity.formatCPU(m.cpuCores)
    }

    private func nodeMemPercent(_ node: Node, clusterId: String) -> Double? {
        guard let m = nodeMetrics(node, clusterId: clusterId),
              let capStr = node.status?.capacity?["memory"] else { return nil }
        let capacity = K8sQuantity.parseMemory(capStr)
        guard capacity > 0 else { return nil }
        return m.memoryBytes / capacity
    }

    private func nodeMemLabel(_ node: Node, clusterId: String) -> String {
        guard let m = nodeMetrics(node, clusterId: clusterId) else { return "-" }
        let capStr = node.status?.capacity?["memory"] ?? ""
        let cap = K8sQuantity.parseMemory(capStr)
        if cap > 0 {
            return "\(K8sQuantity.formatMemory(m.memoryBytes))/\(K8sQuantity.formatMemory(cap))"
        }
        return K8sQuantity.formatMemory(m.memoryBytes)
    }
}

// MARK: - Mini Usage Bar (for table columns)

struct MiniUsageBar: View {
    let value: Double?  // 0.0-1.0+ (nil = no data)
    let label: String
    let color: Color

    var body: some View {
        if let pct = value {
            VStack(alignment: .leading, spacing: 1) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.primary.opacity(0.08))
                            .frame(height: 4)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(barColor(pct))
                            .frame(width: max(2, geo.size.width * min(pct, 1.0)), height: 4)
                    }
                }
                .frame(height: 4)
                Text(label)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } else {
            Text(label)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
    }

    private func barColor(_ pct: Double) -> Color {
        if pct > 0.9 { return .red }
        if pct > 0.7 { return .orange }
        return color
    }
}

// MARK: - Row Protocol & Types

protocol ResourceRow {
    var resourceId: ResourceIdentifier { get }
}

struct PodRow: Identifiable, ResourceRow { let id: ResourceIdentifier; let pod: Pod; let clusterId: String; var resourceId: ResourceIdentifier { id } }
struct DeploymentRow: Identifiable, ResourceRow { let id: ResourceIdentifier; let deployment: Deployment; let clusterId: String; var resourceId: ResourceIdentifier { id } }
struct ServiceRow: Identifiable, ResourceRow { let id: ResourceIdentifier; let service: Service; let clusterId: String; var resourceId: ResourceIdentifier { id } }
struct NodeRow: Identifiable, ResourceRow { let id: ResourceIdentifier; let node: Node; let clusterId: String; var resourceId: ResourceIdentifier { id } }
struct StatefulSetRow: Identifiable, ResourceRow { let id: ResourceIdentifier; let statefulSet: StatefulSet; let clusterId: String; var resourceId: ResourceIdentifier { id } }
struct DaemonSetRow: Identifiable, ResourceRow { let id: ResourceIdentifier; let daemonSet: DaemonSet; let clusterId: String; var resourceId: ResourceIdentifier { id } }
struct ReplicaSetRow: Identifiable, ResourceRow { let id: ResourceIdentifier; let replicaSet: ReplicaSet; let clusterId: String; var resourceId: ResourceIdentifier { id } }
struct JobRow: Identifiable, ResourceRow { let id: ResourceIdentifier; let job: Job; let clusterId: String; var resourceId: ResourceIdentifier { id } }
struct CronJobRow: Identifiable, ResourceRow { let id: ResourceIdentifier; let cronJob: CronJob; let clusterId: String; var resourceId: ResourceIdentifier { id } }
struct ConfigMapRow: Identifiable, ResourceRow { let id: ResourceIdentifier; let configMap: ConfigMap; let clusterId: String; var resourceId: ResourceIdentifier { id } }
struct SecretRow: Identifiable, ResourceRow { let id: ResourceIdentifier; let secret: Secret; let clusterId: String; var resourceId: ResourceIdentifier { id } }
struct IngressRow: Identifiable, ResourceRow { let id: ResourceIdentifier; let ingress: Ingress; let clusterId: String; var resourceId: ResourceIdentifier { id } }
struct IngressClassRow: Identifiable, ResourceRow { let id: ResourceIdentifier; let ingressClass: IngressClass; let clusterId: String; var resourceId: ResourceIdentifier { id } }
struct PersistentVolumeRow: Identifiable, ResourceRow { let id: ResourceIdentifier; let persistentVolume: PersistentVolume; let clusterId: String; var resourceId: ResourceIdentifier { id } }
struct PersistentVolumeClaimRow: Identifiable, ResourceRow { let id: ResourceIdentifier; let persistentVolumeClaim: PersistentVolumeClaim; let clusterId: String; var resourceId: ResourceIdentifier { id } }
struct NetworkPolicyRow: Identifiable, ResourceRow { let id: ResourceIdentifier; let networkPolicy: NetworkPolicy; let clusterId: String; var resourceId: ResourceIdentifier { id } }
struct ServiceAccountRow: Identifiable, ResourceRow { let id: ResourceIdentifier; let serviceAccount: ServiceAccount; let clusterId: String; var resourceId: ResourceIdentifier { id } }
struct HPARow: Identifiable, ResourceRow { let id: ResourceIdentifier; let hpa: HorizontalPodAutoscaler; let clusterId: String; var resourceId: ResourceIdentifier { id } }
struct NamespaceRow: Identifiable, ResourceRow { let id: ResourceIdentifier; let ns: Namespace; let clusterId: String; var resourceId: ResourceIdentifier { id } }
struct EndpointsRow: Identifiable, ResourceRow { let id: ResourceIdentifier; let endpoints: Endpoints; let clusterId: String; var resourceId: ResourceIdentifier { id } }
struct RoleRow: Identifiable, ResourceRow { let id: ResourceIdentifier; let role: Role; let clusterId: String; var resourceId: ResourceIdentifier { id } }
struct RoleBindingRow: Identifiable, ResourceRow { let id: ResourceIdentifier; let roleBinding: RoleBinding; let clusterId: String; var resourceId: ResourceIdentifier { id } }
struct ClusterRoleRow: Identifiable, ResourceRow { let id: ResourceIdentifier; let clusterRole: ClusterRole; let clusterId: String; var resourceId: ResourceIdentifier { id } }
struct ClusterRoleBindingRow: Identifiable, ResourceRow { let id: ResourceIdentifier; let clusterRoleBinding: ClusterRoleBinding; let clusterId: String; var resourceId: ResourceIdentifier { id } }
struct StorageClassRow: Identifiable, ResourceRow { let id: ResourceIdentifier; let storageClass: StorageClass; let clusterId: String; var resourceId: ResourceIdentifier { id } }
struct ResourceQuotaRow: Identifiable, ResourceRow { let id: ResourceIdentifier; let resourceQuota: ResourceQuota; let clusterId: String; var resourceId: ResourceIdentifier { id } }
struct PodDisruptionBudgetRow: Identifiable, ResourceRow { let id: ResourceIdentifier; let podDisruptionBudget: PodDisruptionBudget; let clusterId: String; var resourceId: ResourceIdentifier { id } }
struct LimitRangeRow: Identifiable, ResourceRow { let id: ResourceIdentifier; let limitRange: LimitRange; let clusterId: String; var resourceId: ResourceIdentifier { id } }
struct PriorityClassRow: Identifiable, ResourceRow { let id: ResourceIdentifier; let priorityClass: PriorityClass; let clusterId: String; var resourceId: ResourceIdentifier { id } }
struct LeaseRow: Identifiable, ResourceRow { let id: ResourceIdentifier; let lease: Lease; let clusterId: String; var resourceId: ResourceIdentifier { id } }
struct MutatingWebhookRow: Identifiable, ResourceRow { let id: ResourceIdentifier; let config: MutatingWebhookConfiguration; let clusterId: String; var resourceId: ResourceIdentifier { id } }
struct ValidatingWebhookRow: Identifiable, ResourceRow { let id: ResourceIdentifier; let config: ValidatingWebhookConfiguration; let clusterId: String; var resourceId: ResourceIdentifier { id } }
