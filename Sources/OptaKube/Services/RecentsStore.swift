import Foundation

/// Tracks recently opened resources from the command palette so the empty-query
/// default view shows MRU entries first. Bounded; persisted in UserDefaults.
@MainActor
final class RecentsStore {
    static let shared = RecentsStore()

    struct Entry: Codable, Hashable, Identifiable {
        var clusterId: String
        var resourceTypeRaw: String
        var name: String
        var namespace: String?
        var lastUsed: Date

        var id: String { "\(clusterId)|\(resourceTypeRaw)|\(namespace ?? "")|\(name)" }
        var resourceType: ResourceType? { ResourceType(rawValue: resourceTypeRaw) }
    }

    private let key = "recentResources.v1"
    private let limit = 20

    func all() -> [Entry] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let entries = try? JSONDecoder().decode([Entry].self, from: data) else {
            return []
        }
        return entries.sorted { $0.lastUsed > $1.lastUsed }
    }

    func record(resource: ResourceIdentifier) {
        var entries = all()
        let new = Entry(
            clusterId: resource.clusterId,
            resourceTypeRaw: resource.resourceType.rawValue,
            name: resource.name,
            namespace: resource.namespace,
            lastUsed: Date()
        )
        // Dedupe by id, then prepend.
        entries.removeAll { $0.id == new.id }
        entries.insert(new, at: 0)
        if entries.count > limit { entries = Array(entries.prefix(limit)) }
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    /// Drop entries that point at clusters the user no longer has connected.
    /// Avoids showing zombie recents from kubeconfigs that have been removed.
    func prune(connectedClusterIds: Set<String>) {
        let entries = all().filter { connectedClusterIds.contains($0.clusterId) }
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
