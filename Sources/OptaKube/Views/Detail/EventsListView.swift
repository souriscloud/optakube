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
    @State private var watchTask: Task<Void, Never>?

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
        .onAppear { startWatching() }
        .onDisappear { watchTask?.cancel(); watchTask = nil }
        .onChange(of: resource) { _, _ in startWatching() }
    }

    /// List the resource's events once for the initial render, then hold a live watch
    /// from that list's resourceVersion — applying ADDED/MODIFIED/DELETED in place. The
    /// server periodically closes long-lived watches and may expire the resourceVersion
    /// (410 Gone); both cases just loop back to a fresh list + re-watch, with exponential
    /// backoff on hard failures. Replaces the old 5s relist poll.
    private func startWatching() {
        watchTask?.cancel()
        let resource = self.resource
        isLoading = true
        watchTask = Task {
            guard let client = viewModel.activeClients[resource.clusterId] else {
                await MainActor.run { isLoading = false }
                return
            }
            let displayName = resource.resourceType.displayName
            let kind = String(displayName.dropLast(displayName.hasSuffix("s") ? 1 : 0))
            var failCount = 0

            while !Task.isCancelled && failCount < 5 {
                do {
                    let result = try await client.listEventsForResourceWithVersion(
                        kind: kind, name: resource.name, namespace: resource.namespace
                    )
                    if Task.isCancelled { return }
                    await MainActor.run {
                        applyFullList(result.items)
                        isLoading = false
                    }
                    failCount = 0

                    guard let rv = result.resourceVersion else {
                        // No version to watch from — wait a beat and re-list.
                        try await Task.sleep(for: .seconds(10))
                        continue
                    }

                    let stream = client.watchEventsForResource(
                        kind: kind, name: resource.name, namespace: resource.namespace, resourceVersion: rv
                    )
                    for try await event in stream {
                        if Task.isCancelled { return }
                        await MainActor.run { apply(event) }
                    }
                    // Stream closed cleanly (server-side watch timeout) — re-list and re-watch.
                } catch is CancellationError {
                    return
                } catch K8sError.watchGone {
                    // resourceVersion expired — loop back to a fresh list.
                    continue
                } catch {
                    guard !Task.isCancelled else { return }
                    failCount += 1
                    let delay = min(3.0 * pow(3.0, Double(failCount - 1)), 60.0)
                    try? await Task.sleep(for: .seconds(delay))
                }
            }
        }
    }

    @MainActor
    private func applyFullList(_ items: [K8sEvent]) {
        events = items.sorted { ($0.lastTimestamp ?? .distantPast) > ($1.lastTimestamp ?? .distantPast) }
        updateBadge()
    }

    @MainActor
    private func apply(_ event: WatchEvent<K8sEvent>) {
        switch event.type {
        case .ADDED, .MODIFIED:
            if let idx = events.firstIndex(where: { $0.id == event.object.id }) {
                events[idx] = event.object
            } else {
                events.append(event.object)
            }
        case .DELETED:
            events.removeAll { $0.id == event.object.id }
        case .BOOKMARK, .ERROR:
            return
        }
        events.sort { ($0.lastTimestamp ?? .distantPast) > ($1.lastTimestamp ?? .distantPast) }
        updateBadge()
    }

    @MainActor
    private func updateBadge() {
        EventBadgeStore.shared.warningCounts[EventBadgeStore.key(resource)] = events.filter { $0.type == "Warning" }.count
    }
}
