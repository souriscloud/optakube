import SwiftUI

/// Per-resource cache of event counts so the "Events" tab title can show a warning
/// badge without the tab itself being visible.
@MainActor
final class EventBadgeStore: ObservableObject {
    static let shared = EventBadgeStore()
    @Published var warningCounts: [String: Int] = [:]

    static func key(_ rid: ResourceIdentifier) -> String {
        "\(rid.clusterId)|\(rid.resourceType.rawValue)|\(rid.namespace ?? "")|\(rid.name)"
    }
}

struct EventsListView: View {
    @Environment(AppViewModel.self) private var viewModel
    let resource: ResourceIdentifier
    @State private var events: [K8sEvent] = []
    @State private var isLoading = true
    @State private var errorMsg: String?
    @State private var refreshTask: Task<Void, Never>?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading events...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if events.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "bell.slash")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("No events found")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(events) { event in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: event.type == "Warning" ? "exclamationmark.triangle.fill" : "info.circle.fill")
                                    .foregroundStyle(event.type == "Warning" ? .orange : .blue)
                                    .font(.caption)
                                    .padding(.top, 2)

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(event.reason ?? "Unknown")
                                            .fontWeight(.medium)
                                            .font(.subheadline)
                                        Spacer()
                                        Text(event.ageDisplay)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        if let count = event.count, count > 1 {
                                            Text("x\(count)")
                                                .font(.caption)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 1)
                                                .background(.quaternary)
                                                .clipShape(Capsule())
                                        }
                                    }
                                    if let message = event.message {
                                        Text(message)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(3)
                                    }
                                    if let source = event.source?.component {
                                        Text(source)
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 6)
                            Divider().padding(.leading, 32)
                        }
                    }
                }
            }
        }
        .onAppear { startPolling() }
        .onDisappear { refreshTask?.cancel(); refreshTask = nil }
        .onChange(of: resource) { _, _ in startPolling() }
    }

    private func startPolling() {
        refreshTask?.cancel()
        loadEvents()
        // Lightweight 5s poll while the tab is visible. K8s doesn't push events to a
        // resource-scoped subscriber, so a periodic relist is the realistic option.
        refreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                if Task.isCancelled { break }
                await refreshOnce()
            }
        }
    }

    private func refreshOnce() async {
        guard let client = viewModel.activeClients[resource.clusterId] else { return }
        let kind = resource.resourceType.displayName.dropLast(resource.resourceType.displayName.hasSuffix("s") ? 1 : 0)
        if let result = try? await client.listEventsForResource(
            kind: String(kind),
            name: resource.name,
            namespace: resource.namespace
        ) {
            let sorted = result.sorted { ($0.lastTimestamp ?? .distantPast) > ($1.lastTimestamp ?? .distantPast) }
            let warnings = sorted.filter { $0.type == "Warning" }.count
            await MainActor.run {
                events = sorted
                EventBadgeStore.shared.warningCounts[EventBadgeStore.key(resource)] = warnings
            }
        }
    }

    private func loadEvents() {
        guard let client = viewModel.activeClients[resource.clusterId] else { return }
        isLoading = true
        Task {
            do {
                let kind = resource.resourceType.displayName.dropLast(resource.resourceType.displayName.hasSuffix("s") ? 1 : 0)
                let result = try await client.listEventsForResource(
                    kind: String(kind),
                    name: resource.name,
                    namespace: resource.namespace
                )
                let sorted = result.sorted { ($0.lastTimestamp ?? .distantPast) > ($1.lastTimestamp ?? .distantPast) }
                let warnings = sorted.filter { $0.type == "Warning" }.count
                await MainActor.run {
                    events = sorted
                    isLoading = false
                    EventBadgeStore.shared.warningCounts[EventBadgeStore.key(resource)] = warnings
                }
            } catch {
                await MainActor.run {
                    errorMsg = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }
}
