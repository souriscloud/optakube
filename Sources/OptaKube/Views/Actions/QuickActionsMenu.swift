import SwiftUI

struct QuickActionsMenu: View {
    @Environment(AppViewModel.self) private var viewModel
    let resource: ResourceIdentifier
    @State private var showDeleteConfirmation = false
    @State private var showScaleDialog = false
    @State private var showPortForwardSheet = false
    @State private var showRollbackSheet = false
    @State private var showDebugContainerSheet = false
    @State private var scaleReplicas = 1
    @State private var actionError: String?

    var body: some View {
        Menu {
            // --- Workload actions ---
            if canRestart {
                Button { Task { await performRestart() } } label: {
                    Label("Restart", systemImage: "arrow.clockwise")
                }
            }

            if canScale {
                Button { showScaleDialog = true } label: {
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
                Button { Task { await evictPod() } } label: {
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
                Button { Task { await drainNode() } } label: {
                    Label("Drain", systemImage: "arrow.down.to.line.compact")
                }
            }

            // --- Job actions ---
            if resource.resourceType == .jobs {
                Button { Task { await performDelete(); await viewModel.refresh() } } label: {
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
        .sheet(isPresented: $showScaleDialog) {
            ScaleDialog(resourceName: resource.name, currentReplicas: scaleReplicas) { replicas in
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

    // MARK: - Actions

    private func performRestart() async {
        guard let client = viewModel.activeClients[resource.clusterId] else { return }
        try? await client.restart(resourceType: resource.resourceType, name: resource.name, namespace: resource.namespace)
        await viewModel.refresh()
    }

    private func performScale(replicas: Int) async {
        guard let client = viewModel.activeClients[resource.clusterId] else { return }
        try? await client.scale(resourceType: resource.resourceType, name: resource.name, namespace: resource.namespace, replicas: replicas)
        await viewModel.refresh()
    }

    private func performDelete() async {
        guard let client = viewModel.activeClients[resource.clusterId] else { return }
        try? await client.delete(resourceType: resource.resourceType, name: resource.name, namespace: resource.namespace)
        await viewModel.refresh()
    }

    private func triggerCronJob() async {
        guard let client = viewModel.activeClients[resource.clusterId] else { return }
        try? await client.triggerCronJob(name: resource.name, namespace: resource.namespace)
        await viewModel.refresh()
    }

    private func toggleSuspendCronJob() async {
        guard let client = viewModel.activeClients[resource.clusterId] else { return }
        try? await client.suspendCronJob(name: resource.name, namespace: resource.namespace, suspend: !isCronJobSuspended)
        await viewModel.refresh()
    }

    private func evictPod() async {
        guard let client = viewModel.activeClients[resource.clusterId],
              let ns = resource.namespace else { return }
        let eviction: [String: Any] = [
            "apiVersion": "policy/v1",
            "kind": "Eviction",
            "metadata": ["name": resource.name, "namespace": ns]
        ]
        if let body = try? JSONSerialization.data(withJSONObject: eviction) {
            guard let url = URL(string: "\(client.connection.server)/api/v1/namespaces/\(ns)/pods/\(resource.name)/eviction") else { return }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if let token = try? await client.authProvider.token() {
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            _ = try? await URLSession.shared.data(for: req)
        }
        await viewModel.refresh()
    }

    private func cordonNode(unschedule: Bool) async {
        guard let client = viewModel.activeClients[resource.clusterId] else { return }
        let patchBody: [String: Any] = ["spec": ["unschedulable": unschedule]]
        if let body = try? JSONSerialization.data(withJSONObject: patchBody) {
            try? await client.patch(resourceType: .nodes, name: resource.name, namespace: nil, body: body)
        }
        await viewModel.refresh()
    }

    private func drainNode() async {
        // Drain = cordon + evict all pods
        await cordonNode(unschedule: true)
        guard let client = viewModel.activeClients[resource.clusterId] else { return }
        if let pods = try? await client.list(Pod.self, resourceType: .pods, namespace: nil) {
            let nodePods = pods.filter { $0.nodeName == resource.name }
            for pod in nodePods {
                guard let ns = pod.metadata.namespace else { continue }
                // Skip DaemonSet pods and mirror pods
                let isDaemonSet = pod.metadata.ownerReferences?.contains { $0.kind == "DaemonSet" } ?? false
                let isMirror = pod.metadata.annotations?["kubernetes.io/config.mirror"] != nil
                if isDaemonSet || isMirror { continue }

                let eviction: [String: Any] = [
                    "apiVersion": "policy/v1",
                    "kind": "Eviction",
                    "metadata": ["name": pod.name, "namespace": ns]
                ]
                if let body = try? JSONSerialization.data(withJSONObject: eviction) {
                    guard let url = URL(string: "\(client.connection.server)/api/v1/namespaces/\(ns)/pods/\(pod.name)/eviction") else { continue }
                    var req = URLRequest(url: url)
                    req.httpMethod = "POST"
                    req.httpBody = body
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    if let token = try? await client.authProvider.token() {
                        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    }
                    _ = try? await URLSession.shared.data(for: req)
                }
            }
        }
        await viewModel.refresh()
    }
}

// MARK: - Scale Dialog

struct ScaleDialog: View {
    let resourceName: String
    @State var currentReplicas: Int
    let onScale: (Int) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("Scale \(resourceName)")
                .font(.headline)
            Stepper("Replicas: \(currentReplicas)", value: $currentReplicas, in: 0...100)
                .frame(width: 200)
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Scale") { onScale(currentReplicas); dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 300)
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
                            ForEach(ports, id: \.containerPort) { port in
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
                    }
                }
            }
        }
        .padding()
        .frame(width: 340)
    }

    private func startPortForward() {
        guard let lp = Int(localPort), let rp = Int(remotePort) else {
            errorMsg = "Invalid port numbers"
            return
        }
        guard let client = viewModel.activeClients[resource.clusterId] else { return }
        let conn = client.connection

        // Find kubeconfig path from the connection ID (format: "path:contextName")
        let parts = conn.id.split(separator: ":", maxSplits: 1)
        let kubeconfigPath = parts.count > 0 ? String(parts[0]) : nil

        let pf = conn.portForward(
            namespace: resource.namespace ?? "default",
            podName: resource.name,
            localPort: lp,
            remotePort: rp,
            kubeconfigPath: kubeconfigPath,
            context: conn.contextName
        )
        PortForwardManager.shared.add(pf)
        dismiss()
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
                        ForEach(replicaSets, id: \.revision) { rs in
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
