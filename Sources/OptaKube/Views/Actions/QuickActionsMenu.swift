import SwiftUI

struct QuickActionsMenu: View {
    @Environment(AppViewModel.self) private var viewModel
    let resource: ResourceIdentifier
    @State private var showDeleteConfirmation = false
    @State private var showCascadeDeleteConfirmation = false
    @State private var showDrainConfirmation = false
    @State private var showEvictConfirmation = false
    @State private var showScaleDialog = false
    @State private var showPortForwardSheet = false
    @State private var showRollbackSheet = false
    @State private var showDebugContainerSheet = false
    @State private var scaleReplicas = 1
    @State private var actionError: String?
    @State private var actionNotice: String?

    var body: some View {
        Menu {
            // --- Workload actions ---
            if canRestart {
                Button { Task { await performRestart() } } label: {
                    Label("Restart", systemImage: "arrow.clockwise")
                }
            }

            if canScale {
                Button {
                    // Seed from the live count. This used to open at a hardcoded 1, so
                    // pressing the dialog's default button on a 10-replica Deployment
                    // scaled it straight down to 1.
                    scaleReplicas = liveReplicas
                    showScaleDialog = true
                } label: {
                    Label("Scale", systemImage: "arrow.up.arrow.down")
                }
            }

            if resource.resourceType == .deployments {
                Button { showRollbackSheet = true } label: {
                    Label("Rollback", systemImage: "clock.arrow.circlepath")
                }
                Button { Task { await performRestart() } } label: {
                    Label("Rolling Restart", systemImage: "arrow.triangle.2.circlepath")
                }
            }

            // --- CronJob actions ---
            if resource.resourceType == .cronJobs {
                Button { Task { await triggerCronJob() } } label: {
                    Label("Trigger Job", systemImage: "bolt")
                }
                Button { Task { await toggleSuspendCronJob() } } label: {
                    Label(isCronJobSuspended ? "Resume" : "Suspend", systemImage: isCronJobSuspended ? "play" : "pause")
                }
            }

            // --- Pod actions ---
            if resource.resourceType == .pods {
                Button { showPortForwardSheet = true } label: {
                    Label("Port Forward", systemImage: "network")
                }
                Button { showDebugContainerSheet = true } label: {
                    Label("Debug Container", systemImage: "ladybug")
                }
                Button { showEvictConfirmation = true } label: {
                    Label("Evict", systemImage: "arrow.uturn.right")
                }
            }

            // --- Service actions ---
            if resource.resourceType == .services {
                Button { showPortForwardSheet = true } label: {
                    Label("Port Forward", systemImage: "network")
                }
            }

            // --- Node actions ---
            if resource.resourceType == .nodes {
                Button { Task { await cordonNode(unschedule: true) } } label: {
                    Label("Cordon", systemImage: "nosign")
                }
                Button { Task { await cordonNode(unschedule: false) } } label: {
                    Label("Uncordon", systemImage: "checkmark.circle")
                }
                Button { showDrainConfirmation = true } label: {
                    Label("Drain", systemImage: "arrow.down.to.line.compact")
                }
            }

            // --- Job actions ---
            if resource.resourceType == .jobs {
                Button { showCascadeDeleteConfirmation = true } label: {
                    Label("Delete & Cascade", systemImage: "trash.slash")
                }
            }

            // --- Copy name (universal) ---
            Divider()
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

            Divider()

            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .confirmationDialog("Delete \(resource.name)?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                Task { await performDelete() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
        .confirmationDialog("Delete \(resource.name) and its pods?",
                            isPresented: $showCascadeDeleteConfirmation) {
            Button("Delete & Cascade", role: .destructive) {
                Task { await performDelete() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes the Job and every pod it created. This action cannot be undone.")
        }
        .confirmationDialog("Evict \(resource.name)?", isPresented: $showEvictConfirmation) {
            Button("Evict", role: .destructive) {
                Task { await evictPod() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The pod is deleted, subject to any PodDisruptionBudget. Its controller decides whether to replace it.")
        }
        .confirmationDialog("Drain \(resource.name)?", isPresented: $showDrainConfirmation) {
            Button("Cordon & Drain", role: .destructive) {
                Task { await drainNode() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This marks the node unschedulable and evicts every pod on it except DaemonSet and static pods. Workloads will restart elsewhere.")
        }
        .sheet(isPresented: $showScaleDialog) {
            ScaleDialog(resourceName: resource.name, initialReplicas: scaleReplicas) { replicas in
                Task { await performScale(replicas: replicas) }
            }
        }
        .sheet(isPresented: $showPortForwardSheet) {
            PortForwardSheet(resource: resource)
        }
        .sheet(isPresented: $showRollbackSheet) {
            RollbackSheet(resource: resource)
        }
        .sheet(isPresented: $showDebugContainerSheet) {
            DebugContainerSheet(resource: resource)
        }
        // Both outcomes are reported now. Every action below used to be a bare `try?`:
        // on an RBAC denial the list refreshed unchanged and nothing was said, which is
        // indistinguishable from the action having been accepted.
        .alert("Action failed", isPresented: .constant(actionError != nil)) {
            Button("Copy details") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(actionError ?? "", forType: .string)
                actionError = nil
            }
            Button("OK", role: .cancel) { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
        .alert("Done", isPresented: .constant(actionNotice != nil)) {
            Button("OK", role: .cancel) { actionNotice = nil }
        } message: {
            Text(actionNotice ?? "")
        }
    }

    // MARK: - Capability Checks

    private var canRestart: Bool {
        [.deployments, .statefulSets, .daemonSets].contains(resource.resourceType)
    }

    private var canScale: Bool {
        [.deployments, .statefulSets, .replicaSets].contains(resource.resourceType)
    }

    private var isCronJobSuspended: Bool {
        viewModel.cronJobs[resource.clusterId]?.first { $0.name == resource.name }?.isSuspended ?? false
    }

    /// The replica count the cluster currently reports, used to seed the Scale dialog.
    private var liveReplicas: Int {
        switch resource.resourceType {
        case .deployments:
            return viewModel.deployments[resource.clusterId]?
                .first { $0.name == resource.name }?.replicas ?? 1
        case .statefulSets:
            return viewModel.statefulSets[resource.clusterId]?
                .first { $0.name == resource.name }?.replicas ?? 1
        case .replicaSets:
            return viewModel.replicaSets[resource.clusterId]?
                .first { $0.name == resource.name }?.replicas ?? 1
        default:
            return 1
        }
    }

    // MARK: - Actions

    /// Runs a mutating action and reports the outcome either way, then resyncs.
    private func run(_ succeeded: String, _ body: () async throws -> Void) async {
        do {
            try await body()
            actionNotice = succeeded
        } catch {
            actionError = error.localizedDescription
        }
        await viewModel.refresh()
    }

    private func performRestart() async {
        guard let client = viewModel.activeClients[resource.clusterId] else { return }
        await run("Restarted \(resource.name).") {
            try await client.restart(resourceType: resource.resourceType,
                                     name: resource.name, namespace: resource.namespace)
        }
    }

    private func performScale(replicas: Int) async {
        guard let client = viewModel.activeClients[resource.clusterId] else { return }
        await run("Scaled \(resource.name) to \(replicas) replica\(replicas == 1 ? "" : "s").") {
            try await client.scale(resourceType: resource.resourceType, name: resource.name,
                                   namespace: resource.namespace, replicas: replicas)
        }
    }

    private func performDelete() async {
        guard let client = viewModel.activeClients[resource.clusterId] else { return }
        await run("Deleted \(resource.name).") {
            try await client.delete(resourceType: resource.resourceType,
                                    name: resource.name, namespace: resource.namespace)
        }
    }

    private func triggerCronJob() async {
        guard let client = viewModel.activeClients[resource.clusterId] else { return }
        await run("Triggered a job from \(resource.name).") {
            try await client.triggerCronJob(name: resource.name, namespace: resource.namespace)
        }
    }

    private func toggleSuspendCronJob() async {
        guard let client = viewModel.activeClients[resource.clusterId] else { return }
        let suspend = !isCronJobSuspended
        await run("\(suspend ? "Suspended" : "Resumed") \(resource.name).") {
            try await client.suspendCronJob(name: resource.name,
                                            namespace: resource.namespace, suspend: suspend)
        }
    }

    private func evictPod() async {
        guard let client = viewModel.activeClients[resource.clusterId] else { return }
        guard let ns = resource.namespace else {
            actionError = "This pod has no namespace, so it cannot be evicted."
            return
        }
        await run("Evicted \(resource.name).") {
            try await client.evict(podName: resource.name, namespace: ns)
        }
    }

    private func cordonNode(unschedule: Bool) async {
        guard let client = viewModel.activeClients[resource.clusterId] else { return }
        await run("\(unschedule ? "Cordoned" : "Uncordoned") \(resource.name).") {
            let body = try JSONSerialization.data(withJSONObject: ["spec": ["unschedulable": unschedule]])
            try await client.patch(resourceType: .nodes, name: resource.name,
                                   namespace: nil, body: body)
        }
    }

    private func drainNode() async {
        guard let client = viewModel.activeClients[resource.clusterId] else { return }

        // Drain = cordon, then evict everything that isn't managed by a DaemonSet or
        // mirrored from a static manifest. Report per-pod failures rather than
        // discarding them: a PodDisruptionBudget blocking an eviction is the normal
        // case, and the user needs to know the node isn't actually clear.
        var failures: [String] = []
        do {
            let body = try JSONSerialization.data(withJSONObject: ["spec": ["unschedulable": true]])
            try await client.patch(resourceType: .nodes, name: resource.name, namespace: nil, body: body)
        } catch {
            actionError = "Couldn't cordon \(resource.name), so drain was not attempted.\n\n"
                + error.localizedDescription
            await viewModel.refresh()
            return
        }

        var evicted = 0
        do {
            let pods = try await client.list(Pod.self, resourceType: .pods, namespace: nil)
            let nodePods = pods.filter { $0.nodeName == resource.name }
            for pod in nodePods {
                guard let ns = pod.metadata.namespace else { continue }
                let isDaemonSet = pod.metadata.ownerReferences?.contains { $0.kind == "DaemonSet" } ?? false
                let isMirror = pod.metadata.annotations?["kubernetes.io/config.mirror"] != nil
                if isDaemonSet || isMirror { continue }
                do {
                    try await client.evict(podName: pod.name, namespace: ns)
                    evicted += 1
                } catch {
                    failures.append("\(ns)/\(pod.name): \(error.localizedDescription)")
                }
            }
        } catch {
            actionError = "Cordoned \(resource.name), but couldn't list its pods to evict them.\n\n"
                + error.localizedDescription
            await viewModel.refresh()
            return
        }

        if failures.isEmpty {
            actionNotice = "Drained \(resource.name) — cordoned and evicted \(evicted) pod\(evicted == 1 ? "" : "s")."
        } else {
            actionError = "Cordoned \(resource.name) and evicted \(evicted) pod\(evicted == 1 ? "" : "s"), "
                + "but \(failures.count) could not be evicted:\n\n"
                + failures.prefix(10).joined(separator: "\n")
                + (failures.count > 10 ? "\n… and \(failures.count - 10) more." : "")
        }
        await viewModel.refresh()
    }
}

// MARK: - Scale Dialog

struct ScaleDialog: View {
    let resourceName: String
    /// The cluster's current replica count. `@State` is deliberately not initialised
    /// from this: SwiftUI only honours a `@State` initial value the first time a view
    /// identity appears, so a reused sheet would keep a stale seed.
    let initialReplicas: Int
    let onScale: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var edited: Int?

    private var value: Int { edited ?? initialReplicas }

    var body: some View {
        VStack(spacing: 16) {
            Text("Scale \(resourceName)")
                .font(.headline)
            Text("Currently \(initialReplicas) replica\(initialReplicas == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
            Stepper("Replicas: \(value)",
                    value: Binding(get: { value }, set: { edited = $0 }),
                    in: 0...500)
                .frame(width: 220)
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(value == 0 ? "Scale to zero" : "Scale") { onScale(value); dismiss() }
                    .keyboardShortcut(.defaultAction)
                    // Nothing to do when untouched — and it keeps a reflexive Return
                    // from being a production change.
                    .disabled(value == initialReplicas)
            }
        }
        .padding()
        .frame(width: 320)
    }
}

// MARK: - Port Forward Sheet

struct PortForwardSheet: View {
    @Environment(AppViewModel.self) private var viewModel
    let resource: ResourceIdentifier
    @Environment(\.dismiss) private var dismiss
    @State private var localPort: String = "8080"
    @State private var remotePort: String = "80"
    @State private var errorMsg: String?

    var body: some View {
        VStack(spacing: 16) {
            Text("Port Forward")
                .font(.headline)
            Text(resource.name)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                VStack(alignment: .leading) {
                    Text("Local Port").font(.caption).foregroundStyle(.secondary)
                    TextField("8080", text: $localPort)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                }
                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading) {
                    Text("Remote Port").font(.caption).foregroundStyle(.secondary)
                    TextField("80", text: $remotePort)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                }
            }

            // Show available ports from pod spec
            if let pod = viewModel.pods[resource.clusterId]?.first(where: { $0.name == resource.name }),
               let containers = pod.spec?.containers {
                let ports = containers.flatMap { $0.ports ?? [] }
                if !ports.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Available ports:").font(.caption).foregroundStyle(.secondary)
                        HStack {
                            // Keyed by position, not by containerPort: a sidecar can
                            // expose the same port as the app, and one container may
                            // legally declare the same port for TCP and UDP. Duplicate
                            // ForEach IDs are undefined behaviour in SwiftUI.
                            ForEach(Array(ports.enumerated()), id: \.offset) { _, port in
                                Button("\(port.containerPort)") {
                                    remotePort = "\(port.containerPort)"
                                    if localPort == "8080" || localPort.isEmpty {
                                        localPort = "\(port.containerPort)"
                                    }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }
                }
            }

            if let err = errorMsg {
                Text(err).foregroundStyle(.red).font(.caption)
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Forward") {
                    startPortForward()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(localPort.isEmpty || remotePort.isEmpty)
            }

            // Show active forwards
            let pfm = PortForwardManager.shared
            if !pfm.activeForwards.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Active Forwards").font(.caption).foregroundStyle(.secondary)
                    ForEach(pfm.activeForwards) { pf in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Circle()
                                    .fill(pf.isRunning ? .green : .red)
                                    .frame(width: 6, height: 6)
                                Text(pf.displayName)
                                    .font(.caption)
                                Spacer()
                                Button { pfm.remove(pf) } label: {
                                    Image(systemName: "xmark.circle")
                                        .font(.caption)
                                }
                                .buttonStyle(.plain)
                            }
                            // kubectl's own words — "address already in use", "unable to
                            // forward port because pod is not running". Captured all
                            // along, just never shown anywhere.
                            if let err = pf.errorMessage, !err.isEmpty {
                                Text(err)
                                    .font(.caption2)
                                    .foregroundStyle(.red)
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .frame(width: 340)
    }

    private func startPortForward() {
        guard let lp = Int(localPort), let rp = Int(remotePort) else {
            errorMsg = "Ports must be numbers."
            return
        }
        guard (1...65535).contains(lp), (1...65535).contains(rp) else {
            errorMsg = "Ports must be between 1 and 65535."
            return
        }
        guard let client = viewModel.activeClients[resource.clusterId] else {
            errorMsg = "Not connected to this cluster."
            return
        }
        let conn = client.connection

        let pf = conn.portForward(
            namespace: resource.namespace ?? "default",
            name: resource.name,
            resourceType: resource.resourceType,
            localPort: lp,
            remotePort: rp,
            kubeconfigPath: conn.kubeconfigPath,
            context: conn.contextName
        )
        errorMsg = nil
        PortForwardManager.shared.add(pf)

        // Hold the sheet open briefly. kubectl reports "address already in use" or
        // "pod is not running" almost immediately, and dismissing straight away meant a
        // forward that never came up looked like it had succeeded.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(800))
            if let err = pf.errorMessage, !err.isEmpty {
                errorMsg = err
            } else if !pf.isRunning {
                errorMsg = "The forward stopped immediately. Check that local port \(lp) is free and the target is running."
            } else {
                dismiss()
            }
        }
    }
}

// MARK: - Rollback Sheet

struct RollbackSheet: View {
    @Environment(AppViewModel.self) private var viewModel
    let resource: ResourceIdentifier
    @Environment(\.dismiss) private var dismiss
    @State private var replicaSets: [(revision: Int, name: String, image: String, date: String)] = []
    @State private var isLoading = true
    @State private var errorMsg: String?
    @State private var showConfirm = false
    @State private var targetRevision: Int?

    var body: some View {
        VStack(spacing: 12) {
            Text("Rollback \(resource.name)")
                .font(.headline)

            if isLoading {
                ProgressView()
            } else if replicaSets.isEmpty {
                Text("No revision history found")
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(spacing: 1) {
                        // Position-keyed: `revision` falls back to 0 for every ReplicaSet
                        // missing the deployment.kubernetes.io/revision annotation, which
                        // would give several rows the same ID.
                        ForEach(Array(replicaSets.enumerated()), id: \.offset) { _, rs in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Revision \(rs.revision)")
                                        .fontWeight(.medium)
                                    Text(rs.image)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                    Text(rs.date)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                                Spacer()
                                if rs.revision == replicaSets.first?.revision {
                                    Text("Current")
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 2)
                                        .background(.blue.opacity(0.15))
                                        .clipShape(Capsule())
                                } else {
                                    Button("Rollback") {
                                        targetRevision = rs.revision
                                        showConfirm = true
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                        }
                    }
                }
                .frame(maxHeight: 250)
            }

            if let err = errorMsg {
                Text(err).foregroundStyle(.red).font(.caption)
            }

            Button("Close") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding()
        .frame(width: 420)
        .confirmationDialog("Rollback to revision \(targetRevision ?? 0)?", isPresented: $showConfirm) {
            Button("Rollback", role: .destructive) {
                if let rev = targetRevision { Task { await performRollback(to: rev) } }
            }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear { loadRevisions() }
    }

    private func loadRevisions() {
        guard let client = viewModel.activeClients[resource.clusterId] else { return }
        Task {
            do {
                let rsList = try await client.listReplicaSetsForDeployment(name: resource.name, namespace: resource.namespace)
                await MainActor.run {
                    replicaSets = rsList.compactMap { rs in
                        guard let revStr = rs.metadata.annotations?["deployment.kubernetes.io/revision"],
                              let rev = Int(revStr) else { return nil }
                        let image = rs.spec?.template?.spec?.containers?.first?.image ?? "unknown"
                        let date = rs.creationTimestamp.map {
                            let f = DateFormatter()
                            f.dateStyle = .short
                            f.timeStyle = .short
                            return f.string(from: $0)
                        } ?? ""
                        return (revision: rev, name: rs.name, image: image, date: date)
                    }
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMsg = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }

    private func performRollback(to revision: Int) async {
        guard let client = viewModel.activeClients[resource.clusterId] else { return }
        do {
            try await client.rollbackDeployment(name: resource.name, namespace: resource.namespace, toRevision: revision)
            await viewModel.refresh()
            await MainActor.run { dismiss() }
        } catch {
            await MainActor.run { errorMsg = error.localizedDescription }
        }
    }
}

// MARK: - Debug Container Sheet

struct DebugContainerSheet: View {
    @Environment(AppViewModel.self) private var viewModel
    let resource: ResourceIdentifier
    @Environment(\.dismiss) private var dismiss
    @State private var containerName = "debug"
    @State private var image = "busybox:latest"
    @State private var errorMsg: String?
    @State private var isCreating = false
    @State private var success = false

    private let commonImages = [
        "busybox:latest",
        "alpine:latest",
        "nicolaka/netshoot:latest",
        "curlimages/curl:latest",
        "ubuntu:latest",
    ]

    var body: some View {
        VStack(spacing: 16) {
            Text("Debug Container")
                .font(.headline)
            Text(resource.name)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text("Container Name").font(.caption).foregroundStyle(.secondary)
                TextField("debug", text: $containerName)
                    .textFieldStyle(.roundedBorder)

                Text("Image").font(.caption).foregroundStyle(.secondary)
                TextField("busybox:latest", text: $image)
                    .textFieldStyle(.roundedBorder)

                Text("Quick Pick:").font(.caption).foregroundStyle(.secondary)
                HStack {
                    ForEach(commonImages, id: \.self) { img in
                        Button(img.split(separator: "/").last?.split(separator: ":").first.map(String.init) ?? img) {
                            image = img
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                }
            }

            if let err = errorMsg {
                Text(err).foregroundStyle(.red).font(.caption).lineLimit(3)
            }

            if success {
                Label("Container added", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Create") {
                    Task { await createDebugContainer() }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(containerName.isEmpty || image.isEmpty || isCreating)
            }
        }
        .padding()
        .frame(width: 380)
    }

    private func createDebugContainer() async {
        guard let client = viewModel.activeClients[resource.clusterId] else { return }
        isCreating = true
        errorMsg = nil
        do {
            try await client.addEphemeralContainer(
                podName: resource.name,
                namespace: resource.namespace,
                containerName: containerName,
                image: image
            )
            await MainActor.run {
                isCreating = false
                success = true
            }
            await viewModel.refresh()
        } catch {
            await MainActor.run {
                errorMsg = error.localizedDescription
                isCreating = false
            }
        }
    }
}
