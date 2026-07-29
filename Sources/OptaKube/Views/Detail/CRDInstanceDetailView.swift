import SwiftUI
import Yams

/// YAML view / edit / apply / delete for a single Custom Resource instance. CRD
/// instances aren't built-in `ResourceType`s, so they don't flow through
/// `ResourceDetailView`; this sheet gives them the same edit-with-diff capability the
/// built-in types get, via the CRD-specific client methods.
struct CRDInstanceDetailView: View {
    let crd: CRDDefinition
    let item: GenericK8sResource
    let clusterId: String
    /// Called after a successful apply/delete so the list can refresh.
    let onChanged: () -> Void

    @Environment(AppViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

    @State private var yamlContent = ""
    @State private var editContent = ""
    @State private var isEditing = false
    @State private var isLoading = true
    @State private var isApplying = false
    @State private var showDiff = false
    @State private var showDeleteConfirm = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if isLoading {
                ProgressView("Loading…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if isEditing {
                editor
            } else {
                YAMLTextView(text: .constant(yamlContent), isEditable: false)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption).foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal).padding(.bottom, 6)
            }
        }
        .frame(minWidth: 560, minHeight: 480)
        .onAppear(perform: load)
        .sheet(isPresented: $showDiff) {
            YAMLDiffView(current: yamlContent, edited: editContent,
                         onConfirm: { showDiff = false; apply() },
                         onCancel: { showDiff = false })
        }
        .confirmationDialog("Delete \(item.name)?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { delete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes the \(crd.kind) \"\(item.name)\".")
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "puzzlepiece.extension")
                .font(.title2).foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).font(.headline)
                Text("\(crd.kind) · \(crd.group)/\(crd.version)\(item.namespace.isEmpty ? "" : " · \(item.namespace)")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if isEditing {
                Button("Cancel") { isEditing = false; errorMessage = nil }
                Button("Review & Apply") { errorMessage = nil; showDiff = true }
                    .buttonStyle(.borderedProminent)
                    .disabled(isApplying || editContent == yamlContent)
            } else {
                Button(role: .destructive) { showDeleteConfirm = true } label: {
                    Image(systemName: "trash")
                }
                .help("Delete this resource")
                Button("Edit") { editContent = yamlContent; isEditing = true; errorMessage = nil }
                    .disabled(isLoading)
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding()
    }

    private var editor: some View {
        YAMLTextView(text: $editContent)
    }

    // MARK: - Actions

    private func load() {
        guard let client = viewModel.activeClients[clusterId] else {
            errorMessage = "No active connection."; isLoading = false; return
        }
        isLoading = true
        Task {
            do {
                let data = try await client.getRawCustomResource(crd: crd, name: item.name,
                                                                  namespace: item.namespace.isEmpty ? nil : item.namespace)
                let yaml = Self.jsonDataToYAML(data) ?? item.jsonString
                await MainActor.run { yamlContent = yaml; isLoading = false }
            } catch {
                // Fall back to the already-loaded raw JSON if the live fetch fails.
                await MainActor.run { yamlContent = item.jsonString; isLoading = false }
            }
        }
    }

    private func apply() {
        guard let client = viewModel.activeClients[clusterId] else { return }
        let bodyData: Data
        do {
            // Custom resources are the worst case for YAML 1.1 coercion: with
            // x-kubernetes-preserve-unknown-fields the API server stores whatever it is
            // handed, so a silently retyped scalar is never rejected. See ManifestYAML.
            bodyData = try ManifestYAML.jsonData(from: editContent)
        } catch {
            errorMessage = error.localizedDescription; return
        }
        isApplying = true
        Task {
            do {
                try await client.replaceCustomResource(crd: crd, name: item.name,
                                                        namespace: item.namespace.isEmpty ? nil : item.namespace, body: bodyData)
                await MainActor.run { yamlContent = editContent; isEditing = false; isApplying = false; onChanged() }
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription; isApplying = false }
            }
        }
    }

    private func delete() {
        guard let client = viewModel.activeClients[clusterId] else { return }
        Task {
            do {
                try await client.deleteCustomResource(crd: crd, name: item.name,
                                                      namespace: item.namespace.isEmpty ? nil : item.namespace)
                await MainActor.run { onChanged(); dismiss() }
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription }
            }
        }
    }

    private static func jsonDataToYAML(_ data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return try? Yams.dump(object: json, sortKeys: true)
    }
}
