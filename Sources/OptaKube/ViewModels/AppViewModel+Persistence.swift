import Foundation

// MARK: - State Persistence (keyed by cluster IDs for stable recall)

extension AppViewModel {
    /// Stable key based on connected cluster IDs — same clusters = same saved state
    private var stateKey: String {
        let sortedIds = selectedClusterIds.sorted().joined(separator: "+")
        return "clusterState.\(sortedIds)"
    }

    func saveState() {
        guard !selectedClusterIds.isEmpty else { return }
        let state = WindowState(
            namespace: selectedNamespace,
            resourceType: selectedResourceType.rawValue,
            clusterIds: Array(selectedClusterIds)
        )
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: stateKey)
        }
    }

    func restoreState() {
        guard !selectedClusterIds.isEmpty else { return }
        guard let data = UserDefaults.standard.data(forKey: stateKey),
              let state = try? JSONDecoder().decode(WindowState.self, from: data) else { return }

        if let ns = state.namespace {
            selectedNamespace = ns
        }
        if let rt = ResourceType(rawValue: state.resourceType) {
            selectedResourceType = rt
        }
    }
}

// MARK: - Persisted Window State

struct WindowState: Codable {
    var namespace: String?
    var resourceType: String
    var clusterIds: [String]
}
