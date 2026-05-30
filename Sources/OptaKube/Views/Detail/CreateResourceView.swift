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

        guard let gvr = resolveGVR(apiVersion: apiVersion, kind: kind) else {
            errorMessage = "Unknown kind \"\(kind)\" for \(apiVersion). If it's a CRD, open that cluster's CRDs first so it's discovered."
            return
        }

        let manifestNS = meta["namespace"] as? String
        let ns = gvr.namespaced ? (manifestNS ?? viewModel.selectedNamespace ?? "default") : nil
        let apiPath = apiVersion.contains("/") ? "/apis/\(apiVersion)" : "/api/\(apiVersion)"
        let path: String
        if let ns {
            path = "\(apiPath)/namespaces/\(ns)/\(gvr.plural)/\(name)"
        } else {
            path = "\(apiPath)/\(gvr.plural)/\(name)"
        }

        isApplying = true
        Task {
            do {
                try await client.serverSideApply(path: path, yaml: text)
                await MainActor.run {
                    isApplying = false
                    successMessage = "Applied \(kind)/\(name)\(ns.map { " in \($0)" } ?? "")."
                    Task { await viewModel.refresh() }
                }
            } catch {
                await MainActor.run { isApplying = false; errorMessage = error.localizedDescription }
            }
        }
    }

    private struct GVR { let plural: String; let namespaced: Bool }

    /// Resolve a manifest's (apiVersion, kind) to its resource plural + scope, using the
    /// built-in types first, then any CRDs discovered on the connected cluster.
    private func resolveGVR(apiVersion: String, kind: String) -> GVR? {
        if let rt = ResourceType.allCases.first(where: { $0.kind == kind }) {
            return GVR(plural: rt.resource, namespaced: rt.isNamespaced)
        }
        let group = apiVersion.contains("/") ? String(apiVersion.split(separator: "/").first ?? "") : ""
        if let crd = viewModel.discoveredCRDs.first(where: { $0.kind == kind && $0.group == group }) {
            return GVR(plural: crd.plural, namespaced: crd.isNamespaced)
        }
        return nil
    }

    private func clusterName(_ id: String) -> String {
        viewModel.availableConnections.first { $0.id == id }?.name ?? id
    }
}
