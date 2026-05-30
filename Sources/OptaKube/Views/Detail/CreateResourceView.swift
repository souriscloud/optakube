import SwiftUI
import Yams

/// Paste (or drop) a YAML manifest and apply it to the cluster via server-side apply —
/// the "create new resource" path the app otherwise lacked (editing was limited to
/// existing resources). Routes by the manifest's apiVersion + kind, resolving the
/// resource path against the built-in types and discovered CRDs.
struct CreateResourceView: View {
    @Environment(AppViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

    @State private var clusterId: String = ""
    @State private var text: String = CreateResourceView.template
    @State private var isApplying = false
    @State private var errorMessage: String?
    @State private var successMessage: String?

    static let template = """
    apiVersion: v1
    kind: ConfigMap
    metadata:
      name: example
      namespace: default
    data:
      key: value
    """

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(6)
            if let errorMessage {
                banner(errorMessage, color: .red, icon: "exclamationmark.triangle.fill")
            } else if let successMessage {
                banner(successMessage, color: .green, icon: "checkmark.circle.fill")
            }
        }
        .frame(minWidth: 560, minHeight: 480)
        .onAppear {
            if clusterId.isEmpty { clusterId = viewModel.selectedClusterIds.sorted().first ?? "" }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.square.on.square").font(.title2).foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text("Create Resource").font(.headline)
                Text("Paste a YAML manifest — applied with server-side apply")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if viewModel.selectedClusterIds.count > 1 {
                Picker("", selection: $clusterId) {
                    ForEach(viewModel.selectedClusterIds.sorted(), id: \.self) { id in
                        Text(clusterName(id)).tag(id)
                    }
                }
                .labelsHidden().frame(maxWidth: 180)
            }
            Button("Cancel") { dismiss() }
            Button("Apply") { apply() }
                .buttonStyle(.borderedProminent)
                .disabled(isApplying || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding()
    }

    private func banner(_ msg: String, color: Color, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(color)
            Text(msg).font(.caption).foregroundStyle(color).lineLimit(3)
            Spacer()
        }
        .padding(.horizontal).padding(.vertical, 6)
        .background(color.opacity(0.08))
    }

    // MARK: - Apply

    private func apply() {
        errorMessage = nil; successMessage = nil
        guard let client = viewModel.activeClients[clusterId] else {
            errorMessage = "No active connection."; return
        }
        let parsed: [String: Any]
        do {
            guard let obj = try Yams.load(yaml: text) as? [String: Any] else {
                errorMessage = "Manifest must be a single YAML object."; return
            }
            parsed = obj
        } catch {
            errorMessage = "Invalid YAML: \(error.localizedDescription)"; return
        }

        guard let apiVersion = parsed["apiVersion"] as? String, !apiVersion.isEmpty,
              let kind = parsed["kind"] as? String, !kind.isEmpty,
              let meta = parsed["metadata"] as? [String: Any],
              let name = meta["name"] as? String, !name.isEmpty else {
            errorMessage = "Manifest needs apiVersion, kind, and metadata.name."; return
        }

        let manifestNS = meta["namespace"] as? String
        guard let path = ManifestRouting.resourcePath(apiVersion: apiVersion, kind: kind, name: name,
                                                       namespace: manifestNS, crds: viewModel.discoveredCRDs,
                                                       fallbackNamespace: viewModel.selectedNamespace ?? "default") else {
            errorMessage = "Unknown kind \"\(kind)\" for \(apiVersion). If it's a CRD, open that cluster's CRDs first so it's discovered."
            return
        }

        isApplying = true
        Task {
            do {
                try await client.serverSideApply(path: path, yaml: text)
                await MainActor.run {
                    isApplying = false
                    successMessage = "Applied \(kind)/\(name)."
                    Task { await viewModel.refresh() }
                }
            } catch {
                await MainActor.run { isApplying = false; errorMessage = error.localizedDescription }
            }
        }
    }

    private func clusterName(_ id: String) -> String {
        viewModel.availableConnections.first { $0.id == id }?.name ?? id
    }
}
