import SwiftUI

/// Cluster-wide (or namespace-wide) event firehose — every event in the selected
/// namespace across connected clusters, newest first, with a Warnings-only toggle.
/// Complements the per-resource `EventsListView` for triage.
struct EventsBrowserView: View {
    @Environment(AppViewModel.self) private var viewModel
    @State private var warningsOnly = false

    struct EventRow: Identifiable {
        let clusterId: String
        let event: K8sEvent
        var id: String { "\(clusterId)/\(event.id)" }
    }

    private var rows: [EventRow] {
        var all: [EventRow] = []
        for clusterId in viewModel.selectedClusterIds {
            for ev in viewModel.clusterEvents[clusterId] ?? [] {
                all.append(EventRow(clusterId: clusterId, event: ev))
            }
        }
        if warningsOnly { all = all.filter { $0.event.type == "Warning" } }
        if !viewModel.searchText.isEmpty {
            let q = viewModel.searchText
            all = all.filter {
                ($0.event.message?.localizedCaseInsensitiveContains(q) ?? false) ||
                ($0.event.reason?.localizedCaseInsensitiveContains(q) ?? false) ||
                ($0.event.involvedObject?.name?.localizedCaseInsensitiveContains(q) ?? false)
            }
        }
        // Newest first.
        return all.sorted {
            ($0.event.lastTimestamp ?? $0.event.firstTimestamp ?? .distantPast) >
            ($1.event.lastTimestamp ?? $1.event.firstTimestamp ?? .distantPast)
        }
    }

    private var warningCount: Int {
        viewModel.selectedClusterIds.reduce(0) { acc, cid in
            acc + (viewModel.clusterEvents[cid] ?? []).filter { $0.type == "Warning" }.count
        }
    }

    var body: some View {
        Group {
            if viewModel.isLoading && rows.isEmpty {
                ProgressView("Loading events…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if rows.isEmpty {
                ContentUnavailableView {
                    Label(warningsOnly ? "No warnings" : "No events", systemImage: "bell.slash")
                } description: {
                    Text(viewModel.selectedNamespace.map { "Namespace \"\($0)\"." } ?? "All namespaces.")
                }
            } else {
                Table(rows) {
                    TableColumn("") { row in
                        ResourceStatusBadge(status: row.event.resourceStatus)
                    }.width(24)
                    TableColumn("Type") { row in
                        Text(row.event.type ?? "—")
                            .font(.caption)
                            .foregroundStyle(row.event.type == "Warning" ? Color.orange : .secondary)
                    }.width(70)
                    TableColumn("Reason") { row in Text(row.event.reason ?? "—").font(.caption).fontWeight(.medium) }.width(min: 100, ideal: 160)
                    TableColumn("Object") { row in
                        Text("\(row.event.involvedObject?.kind ?? "")/\(row.event.involvedObject?.name ?? "")")
                            .font(.caption).lineLimit(1).truncationMode(.middle)
                    }.width(min: 120, ideal: 220)
                    TableColumn("Message") { row in Text(row.event.message ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(2) }.width(min: 200, ideal: 460)
                    TableColumn("Count") { row in Text("\(row.event.count ?? 1)").monospacedDigit().foregroundStyle(.secondary) }.width(50)
                    TableColumn("Age") { row in Text(row.event.ageDisplay).foregroundStyle(.secondary) }.width(50)
                }
            }
        }
        .navigationTitle("Events")
        .safeAreaInset(edge: .top) {
            HStack(spacing: 8) {
                Circle().fill(.green).frame(width: 7, height: 7)
                Text("\(rows.count) event\(rows.count == 1 ? "" : "s")").font(.caption).foregroundStyle(.secondary)
                if warningCount > 0 {
                    Text("\(warningCount) warning\(warningCount == 1 ? "" : "s")")
                        .font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.orange.opacity(0.15)).foregroundStyle(.orange).clipShape(Capsule())
                }
                Spacer()
                Toggle("Warnings only", isOn: $warningsOnly)
                    .toggleStyle(.checkbox).font(.caption)
                if viewModel.isLoading { ProgressView().controlSize(.small) }
            }
            .padding(.horizontal).padding(.vertical, 4).background(.bar)
        }
        .onAppear { if viewModel.clusterEvents.isEmpty { Task { await viewModel.loadClusterEvents() } } }
    }
}
