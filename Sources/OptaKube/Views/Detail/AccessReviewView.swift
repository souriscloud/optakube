import SwiftUI

/// "Can I…?" matrix — runs `SelfSubjectAccessReview` for the connected kubeconfig
/// identity across every built-in resource type × common verb, scoped to the selected
/// namespace. Mirrors `kubectl auth can-i --list` but as a readable grid, so you can
/// see at a glance what the current credentials are actually allowed to do.
struct AccessReviewView: View {
    @Environment(AppViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

    /// clusterId being reviewed (defaults to the first connected cluster).
    @State private var clusterId: String = ""
    @State private var results: [String: K8sAPIClient.AccessReviewResult] = [:]
    @State private var isRunning = false
    @State private var errorMessage: String?
    @State private var reviewTask: Task<Void, Never>?

    private let verbs = ["get", "list", "watch", "create", "update", "delete"]

    private func key(_ type: ResourceType, _ verb: String) -> String { "\(type.rawValue)|\(verb)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if let errorMessage {
                ContentUnavailableView {
                    Label("Access review failed", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView([.vertical, .horizontal]) {
                    matrix
                        .padding()
                }
            }
        }
        .frame(minWidth: 620, minHeight: 480)
        .onAppear {
            if clusterId.isEmpty { clusterId = viewModel.selectedClusterIds.sorted().first ?? "" }
            runReview()
        }
        .onDisappear { reviewTask?.cancel() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.shield")
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text("Access Review")
                    .font(.headline)
                Text("What the current credentials can do in **\(viewModel.selectedNamespace ?? "all namespaces")**")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if viewModel.selectedClusterIds.count > 1 {
                Picker("Cluster", selection: $clusterId) {
                    ForEach(viewModel.selectedClusterIds.sorted(), id: \.self) { id in
                        Text(clusterName(id)).tag(id)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 200)
                .onChange(of: clusterId) { _, _ in runReview() }
            }

            if isRunning {
                ProgressView().controlSize(.small)
            } else {
                Button {
                    runReview()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Re-run review")
            }

            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding()
    }

    // MARK: - Matrix

    private var matrix: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
            // Header row
            GridRow {
                Text("Resource")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .gridColumnAlignment(.leading)
                ForEach(verbs, id: \.self) { verb in
                    Text(verb)
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .frame(width: 56)
                }
            }
            Divider()
            ForEach(ResourceType.allCases) { type in
                GridRow {
                    HStack(spacing: 6) {
                        Image(systemName: type.systemImage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 16)
                        Text(type.displayName)
                            .font(.callout)
                    }
                    ForEach(verbs, id: \.self) { verb in
                        cell(for: results[key(type, verb)])
                            .frame(width: 56)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cell(for result: K8sAPIClient.AccessReviewResult?) -> some View {
        if let result {
            Image(systemName: result.allowed ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(result.allowed ? Color.green : Color.secondary.opacity(0.5))
                .help(result.allowed ? "Allowed" : (result.reason ?? "Denied"))
        } else if isRunning {
            ProgressView().controlSize(.mini)
        } else {
            Text("–").foregroundStyle(.tertiary)
        }
    }

    // MARK: - Run

    private func clusterName(_ id: String) -> String {
        viewModel.availableConnections.first { $0.id == id }?.name ?? id
    }

    private func runReview() {
        reviewTask?.cancel()
        guard let client = viewModel.activeClients[clusterId] else {
            errorMessage = "No active connection for the selected cluster."
            return
        }
        let namespace = viewModel.selectedNamespace
        let verbs = self.verbs
        results = [:]
        errorMessage = nil
        isRunning = true

        reviewTask = Task {
            var collected: [String: K8sAPIClient.AccessReviewResult] = [:]
            var firstError: String?

            // Bounded concurrency: review each (type, verb) probe in parallel but cap
            // in-flight requests so we don't open ~120 sockets against the API server at once.
            await withTaskGroup(of: (String, K8sAPIClient.AccessReviewResult?).self) { group in
                var iterator = allProbes(verbs: verbs).makeIterator()
                let maxInFlight = 12
                var active = 0

                func submit() {
                    guard let probe = iterator.next() else { return }
                    active += 1
                    group.addTask {
                        do {
                            let r = try await client.selfSubjectAccessReview(
                                verb: probe.verb,
                                group: probe.type.apiGroupName,
                                resource: probe.type.resource,
                                namespace: probe.type.isNamespaced ? namespace : nil
                            )
                            return (probe.key, r)
                        } catch {
                            return (probe.key, nil)
                        }
                    }
                }

                for _ in 0..<maxInFlight { submit() }
                while let (k, r) = await group.next() {
                    active -= 1
                    if let r { collected[k] = r } else if firstError == nil {
                        firstError = "Some access checks failed (the server may not support SelfSubjectAccessReview)."
                    }
                    if !Task.isCancelled { submit() }
                }
            }

            if Task.isCancelled { return }
            await MainActor.run {
                results = collected
                isRunning = false
                // Only surface an error if literally nothing came back.
                if collected.isEmpty { errorMessage = firstError ?? "No results." }
            }
        }
    }

    private struct Probe { let type: ResourceType; let verb: String; var key: String { "\(type.rawValue)|\(verb)" } }

    private func allProbes(verbs: [String]) -> [Probe] {
        ResourceType.allCases.flatMap { type in verbs.map { Probe(type: type, verb: $0) } }
    }
}
