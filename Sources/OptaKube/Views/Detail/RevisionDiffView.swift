import SwiftUI
import Yams

/// Side-by-side line diff between the live Deployment's pod template and any of
/// its historical ReplicaSet revisions. Used as the "Diff" tab in resource detail
/// for deployments — what you'd reach for before clicking Rollback.
struct RevisionDiffView: View {
    @Environment(AppViewModel.self) private var viewModel
    let resource: ResourceIdentifier

    @State private var revisions: [ReplicaSet] = []
    @State private var selectedRevision: ReplicaSet?
    @State private var currentTemplateYAML: String = ""
    @State private var selectedTemplateYAML: String = ""
    @State private var isLoading = true
    @State private var errorMsg: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let err = errorMsg {
                ContentUnavailableView("Couldn't load revisions", systemImage: "exclamationmark.triangle", description: Text(err))
            } else if isLoading {
                ProgressView("Loading revisions…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if revisions.isEmpty {
                ContentUnavailableView("No previous revisions", systemImage: "clock.arrow.circlepath", description: Text("This Deployment has no historical ReplicaSets to compare against."))
            } else {
                HSplitView {
                    revisionList
                        .frame(minWidth: 180, idealWidth: 220)
                    if selectedRevision != nil {
                        diffView
                    } else {
                        Text("Pick a revision to compare").foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .task { await load() }
        .onChange(of: resource) { _, _ in
            Task { await load() }
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: "rectangle.split.2x1")
            Text("Diff vs revision")
                .font(.headline)
            Spacer()
            if let sel = selectedRevision,
               let rev = sel.metadata.annotations?["deployment.kubernetes.io/revision"] {
                Text("comparing live · rev \(rev)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var revisionList: some View {
        List(revisions, id: \.metadata.uid, selection: Binding<String?>(
            get: { selectedRevision?.metadata.uid },
            set: { uid in
                if let uid, let match = revisions.first(where: { $0.metadata.uid == uid }) {
                    Task { await pick(match) }
                }
            }
        )) { rs in
            let rev = rs.metadata.annotations?["deployment.kubernetes.io/revision"] ?? "?"
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Revision \(rev)").font(.subheadline).fontWeight(.medium)
                    Text(rs.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
            }
            .tag(rs.metadata.uid)
        }
        .listStyle(.sidebar)
    }

    private var diffView: some View {
        let lines = computeDiff(left: currentTemplateYAML, right: selectedTemplateYAML)
        return ScrollView([.vertical, .horizontal]) {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    diffColumn(lines: lines, side: .left, title: "Live")
                    Divider()
                    diffColumn(lines: lines, side: .right, title: "Revision")
                }
            }
        }
    }

    private enum Side { case left, right }

    private func diffColumn(lines: [DiffLine], side: Side, title: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.bar)
            ForEach(lines.indices, id: \.self) { idx in
                let line = lines[idx]
                let text = side == .left ? line.left : line.right
                HStack(spacing: 0) {
                    Text(text ?? " ")
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(rowColor(for: line, side: side))
                }
            }
        }
    }

    private func rowColor(for line: DiffLine, side: Side) -> Color {
        switch line.kind {
        case .equal: return .clear
        case .leftOnly: return side == .left ? .red.opacity(0.15) : .clear
        case .rightOnly: return side == .right ? .green.opacity(0.15) : .clear
        case .modified: return side == .left ? .red.opacity(0.12) : .green.opacity(0.12)
        }
    }

    private func load() async {
        guard let client = viewModel.activeClients[resource.clusterId] else { return }
        isLoading = true
        errorMsg = nil
        do {
            let list = try await client.listReplicaSetsForDeployment(name: resource.name, namespace: resource.namespace)
            // Drop the live (current) ReplicaSet — its template is the deployment's live one.
            let currentRevision = list.first?.metadata.annotations?["deployment.kubernetes.io/revision"]
            let past = list.filter { $0.metadata.annotations?["deployment.kubernetes.io/revision"] != currentRevision }
            let liveYAML = try await fetchCurrentTemplateYAML(client: client)
            await MainActor.run {
                self.revisions = past
                self.currentTemplateYAML = liveYAML
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMsg = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    private func fetchCurrentTemplateYAML(client: K8sAPIClient) async throws -> String {
        let raw = try await client.getRawYAML(resourceType: .deployments, name: resource.name, namespace: resource.namespace)
        guard let json = try JSONSerialization.jsonObject(with: raw) as? [String: Any],
              let spec = json["spec"] as? [String: Any],
              let template = spec["template"] else { return "" }
        return (try? Yams.dump(object: template, sortKeys: true)) ?? ""
    }

    private func pick(_ rs: ReplicaSet) async {
        guard let client = viewModel.activeClients[resource.clusterId] else { return }
        selectedRevision = rs
        selectedTemplateYAML = ""
        do {
            let raw = try await client.getRawYAML(resourceType: .replicaSets, name: rs.name, namespace: resource.namespace)
            if let json = try JSONSerialization.jsonObject(with: raw) as? [String: Any],
               let spec = json["spec"] as? [String: Any],
               let template = spec["template"] {
                let yaml = (try? Yams.dump(object: template, sortKeys: true)) ?? ""
                await MainActor.run { self.selectedTemplateYAML = yaml }
            }
        } catch {
            await MainActor.run { self.errorMsg = error.localizedDescription }
        }
    }

    // MARK: - Diff algorithm
    //
    // Line-aligned diff using `CollectionDifference`. For each line in the left
    // (live) string vs the right (revision) string, emit a row tagged as equal /
    // leftOnly / rightOnly. We pair leftOnly+rightOnly that fall in the same
    // hunk into `modified` rows so the visual side-by-side lines up rather than
    // showing every change as a stacked remove+add.

    private enum DiffKind { case equal, leftOnly, rightOnly, modified }
    private struct DiffLine { let left: String?; let right: String?; let kind: DiffKind }

    private func computeDiff(left: String, right: String) -> [DiffLine] {
        let leftLines = left.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let rightLines = right.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let diff = rightLines.difference(from: leftLines)

        // Walk the original left lines, applying the diff to produce paired output.
        var result: [DiffLine] = []
        var pendingRemoves: [String] = []
        var pendingInserts: [String] = []

        // Build per-index events from the difference.
        var removesByIndex: [Int: String] = [:]
        var insertsByIndex: [Int: String] = [:]
        for change in diff {
            switch change {
            case .remove(let offset, let element, _): removesByIndex[offset] = element
            case .insert(let offset, let element, _): insertsByIndex[offset] = element
            }
        }

        // Apply by walking output positions. We rebuild rightLines in order, but
        // also keep removed lines anchored at their left positions.
        var rightIdx = 0
        var leftIdx = 0
        let totalRight = rightLines.count
        let totalLeft = leftLines.count
        while leftIdx < totalLeft || rightIdx < totalRight {
            // Removes happen at left positions; pair with concurrent inserts.
            if leftIdx < totalLeft, let removed = removesByIndex[leftIdx] {
                pendingRemoves.append(removed)
                leftIdx += 1
                continue
            }
            if rightIdx < totalRight, let inserted = insertsByIndex[rightIdx] {
                pendingInserts.append(inserted)
                rightIdx += 1
                continue
            }
            // Flush any pending pair as modified rows.
            flushPending(&result, removes: &pendingRemoves, inserts: &pendingInserts)
            if leftIdx < totalLeft && rightIdx < totalRight {
                result.append(DiffLine(left: leftLines[leftIdx], right: rightLines[rightIdx], kind: .equal))
                leftIdx += 1
                rightIdx += 1
            } else {
                // Trailing tail (shouldn't happen since diff covers everything).
                break
            }
        }
        flushPending(&result, removes: &pendingRemoves, inserts: &pendingInserts)
        return result
    }

    private func flushPending(_ result: inout [DiffLine], removes: inout [String], inserts: inout [String]) {
        let paired = min(removes.count, inserts.count)
        for i in 0..<paired {
            result.append(DiffLine(left: removes[i], right: inserts[i], kind: .modified))
        }
        if removes.count > paired {
            for r in removes[paired...] {
                result.append(DiffLine(left: r, right: nil, kind: .leftOnly))
            }
        }
        if inserts.count > paired {
            for ins in inserts[paired...] {
                result.append(DiffLine(left: nil, right: ins, kind: .rightOnly))
            }
        }
        removes.removeAll()
        inserts.removeAll()
    }
}
