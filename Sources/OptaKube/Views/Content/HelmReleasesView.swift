import SwiftUI

/// Browse Helm v3 releases across the connected clusters. Lists the latest revision of
/// each release; selecting one opens info / values / manifest / history.
struct HelmReleasesView: View {
    @Environment(AppViewModel.self) private var viewModel
    @State private var selected: HelmRow?

    /// One row per release (latest revision), carrying its owning cluster.
    struct HelmRow: Identifiable {
        let clusterId: String
        let release: HelmRelease
        var id: String { "\(clusterId)/\(release.namespace)/\(release.name)" }
    }

    private var rows: [HelmRow] {
        var latest: [String: HelmRow] = [:]
        for clusterId in viewModel.selectedClusterIds {
            for rel in viewModel.helmReleases[clusterId] ?? [] {
                let key = "\(clusterId)/\(rel.namespace)/\(rel.name)"
                if let existing = latest[key], existing.release.revision >= rel.revision { continue }
                latest[key] = HelmRow(clusterId: clusterId, release: rel)
            }
        }
        let all = latest.values.sorted { ($0.release.namespace, $0.release.name) < ($1.release.namespace, $1.release.name) }
        if viewModel.searchText.isEmpty { return all }
        return all.filter { $0.release.name.localizedCaseInsensitiveContains(viewModel.searchText) }
    }

    var body: some View {
        Group {
            if viewModel.isLoading && rows.isEmpty {
                ProgressView("Loading Helm releases…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if rows.isEmpty {
                ContentUnavailableView {
                    Label("No Helm releases", systemImage: "shippingbox")
                } description: {
                    Text(viewModel.selectedNamespace.map { "No releases in namespace \"\($0)\"." } ?? "No Helm releases found.")
                }
            } else {
                Table(rows) {
                    TableColumn("") { _ in Image(systemName: "shippingbox.fill").foregroundStyle(.tint) }.width(24)
                    TableColumn("Name") { row in
                        Text(row.release.name).fontWeight(.medium)
                            .foregroundStyle(Color(red: 0.29, green: 0.62, blue: 1.0))
                    }.width(min: 130, ideal: 200)
                    TableColumn("Namespace") { row in Text(row.release.namespace) }.width(min: 80, ideal: 120)
                    TableColumn("Rev") { row in Text("\(row.release.revision)").monospacedDigit() }.width(40)
                    TableColumn("Status") { row in
                        Text(row.release.status)
                            .foregroundStyle(statusColor(row.release.status))
                    }.width(90)
                    TableColumn("Chart") { row in Text(row.release.chartDisplay).font(.caption) }.width(min: 100, ideal: 180)
                    TableColumn("App") { row in Text(row.release.appVersion).font(.caption).foregroundStyle(.secondary) }.width(80)
                    TableColumn("Updated") { row in Text(shortDate(row.release.updated)).font(.caption).foregroundStyle(.secondary) }.width(min: 90, ideal: 150)
                }
                .contextMenu(forSelectionType: HelmRow.ID.self) { _ in } primaryAction: { ids in
                    if let id = ids.first, let row = rows.first(where: { $0.id == id }) { selected = row }
                }
            }
        }
        .navigationTitle("Helm Releases")
        .safeAreaInset(edge: .top) {
            HStack(spacing: 8) {
                Circle().fill(.green).frame(width: 7, height: 7)
                Text("\(rows.count) release\(rows.count == 1 ? "" : "s")").font(.caption).foregroundStyle(.secondary)
                Text("double-click to inspect").font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                if viewModel.isLoading { ProgressView().controlSize(.small) }
            }
            .padding(.horizontal).padding(.vertical, 4).background(.bar)
        }
        .onAppear { if viewModel.helmReleases.isEmpty { Task { await viewModel.loadHelmReleases() } } }
        .sheet(item: $selected) { row in
            HelmReleaseDetailView(
                clusterId: row.clusterId,
                releaseName: row.release.name,
                namespace: row.release.namespace,
                latest: row.release
            )
            .environment(viewModel)
        }
    }

    private func statusColor(_ s: String) -> Color {
        switch s.lowercased() {
        case "deployed": return .green
        case "failed": return .red
        case "pending-install", "pending-upgrade", "pending-rollback": return .orange
        case "superseded", "uninstalled": return .secondary
        default: return .secondary
        }
    }

    private func shortDate(_ s: String) -> String {
        guard !s.isEmpty else { return "—" }
        // Helm timestamps look like "2024-01-15T10:30:45.123456789Z" or with offset.
        return String(s.prefix(16)).replacingOccurrences(of: "T", with: " ")
    }
}

/// Tabs for a single release: info, user values, rendered manifest, and revision history.
struct HelmReleaseDetailView: View {
    @Environment(AppViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss
    let clusterId: String
    let releaseName: String
    let namespace: String
    let latest: HelmRelease

    @State private var tab = "info"

    private var history: [HelmRelease] {
        (viewModel.helmReleases[clusterId] ?? [])
            .filter { $0.name == releaseName && $0.namespace == namespace }
            .sorted { $0.revision > $1.revision }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "shippingbox.fill").font(.title2).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(latest.name).font(.headline)
                    Text("\(latest.chartDisplay) · rev \(latest.revision) · \(latest.status) · \(namespace)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding()

            Picker("", selection: $tab) {
                Text("Info").tag("info")
                Text("Values").tag("values")
                Text("Manifest").tag("manifest")
                Text("History (\(history.count))").tag("history")
            }
            .pickerStyle(.segmented).labelsHidden().padding(.horizontal).padding(.bottom, 8)

            Divider()

            switch tab {
            case "values": mono(latest.valuesJSON)
            case "manifest": mono(latest.manifest.isEmpty ? "(no manifest stored)" : latest.manifest)
            case "history": historyList
            default: infoList
            }
        }
        .frame(minWidth: 560, minHeight: 460)
    }

    private var infoList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                row("Chart", latest.chart)
                row("Chart version", latest.chartVersion)
                row("App version", latest.appVersion)
                row("Revision", "\(latest.revision)")
                row("Status", latest.status)
                row("Namespace", namespace)
                row("Updated", latest.updated)
                if !latest.description.isEmpty { row("Description", latest.description) }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var historyList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(history) { rev in
                    HStack(spacing: 10) {
                        Text("rev \(rev.revision)").font(.system(.caption, design: .monospaced)).frame(width: 60, alignment: .leading)
                        Text(rev.status).foregroundStyle(.secondary).frame(width: 90, alignment: .leading)
                        Text(rev.chartDisplay).font(.caption)
                        Spacer()
                        Text(String(rev.updated.prefix(19)).replacingOccurrences(of: "T", with: " "))
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(rev.revision == latest.revision ? Color.accentColor.opacity(0.08) : Color.clear)
                    Divider()
                }
            }
        }
    }

    private func mono(_ text: String) -> some View {
        ScrollView {
            Text(text)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).foregroundStyle(.secondary).frame(width: 110, alignment: .trailing)
            Text(value.isEmpty ? "—" : value).textSelection(.enabled)
            Spacer()
        }
        .font(.callout)
    }
}
