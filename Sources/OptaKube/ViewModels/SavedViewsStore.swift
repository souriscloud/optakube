import Foundation
import Observation

/// A pinned navigation target: a namespace + resource type (+ optional label filter)
/// the user jumps to often. Cluster-agnostic on purpose — a saved view applies within
/// whatever window/cluster set is currently connected, so "prod-ns / deployments /
/// app=api" works across every cluster that has it.
struct SavedView: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var namespace: String?
    var resourceType: String   // ResourceType.rawValue
    var labelFilter: String

    init(id: String = UUID().uuidString, name: String, namespace: String?, resourceType: String, labelFilter: String = "") {
        self.id = id
        self.name = name
        self.namespace = namespace
        self.resourceType = resourceType
        self.labelFilter = labelFilter
    }

    var resolvedType: ResourceType? { ResourceType(rawValue: resourceType) }
}

/// Global store of saved views, persisted in `UserDefaults` under a single key.
/// Mirrors `ClusterCustomizationStore`'s shape (singleton + JSON blob).
@Observable
final class SavedViewsStore {
    static let shared = SavedViewsStore()

    private static let key = "savedViews"

    private(set) var views: [SavedView] = []

    private init() {
        load()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.key),
              let decoded = try? JSONDecoder().decode([SavedView].self, from: data) else { return }
        views = decoded
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(views) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    func add(_ view: SavedView) {
        views.append(view)
        persist()
    }

    func remove(_ id: String) {
        views.removeAll { $0.id == id }
        persist()
    }

    /// True when an equivalent view (same ns + type + filter) is already pinned, so the
    /// UI can offer "unpin" instead of creating duplicates.
    func existing(namespace: String?, resourceType: String, labelFilter: String) -> SavedView? {
        views.first { $0.namespace == namespace && $0.resourceType == resourceType && $0.labelFilter == labelFilter }
    }
}
