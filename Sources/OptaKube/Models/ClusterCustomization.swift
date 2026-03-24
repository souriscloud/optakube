import SwiftUI

struct ClusterCustomization: Codable, Hashable {
    var displayName: String?
    var colorName: String?

    static let availableColors: [(name: String, color: Color)] = [
        ("blue", .blue),
        ("green", .green),
        ("red", .red),
        ("orange", .orange),
        ("purple", .purple),
        ("pink", .pink),
        ("cyan", .cyan),
        ("mint", .mint),
        ("indigo", .indigo),
        ("teal", .teal),
        ("yellow", .yellow),
    ]

    var color: Color {
        guard let colorName else { return .blue }
        return Self.availableColors.first { $0.name == colorName }?.color ?? .blue
    }
}

/// Observable store for cluster customizations — all views react to changes instantly
@Observable
final class ClusterCustomizationStore {
    static let shared = ClusterCustomizationStore()

    private(set) var customizations: [String: ClusterCustomization] = [:]

    private static let storageKey = "clusterCustomizations"

    private init() {
        load()
    }

    func get(for clusterId: String) -> ClusterCustomization {
        customizations[clusterId] ?? ClusterCustomization()
    }

    func set(_ customization: ClusterCustomization, for clusterId: String) {
        customizations[clusterId] = customization
        save()
    }

    func reset(for clusterId: String) {
        customizations.removeValue(forKey: clusterId)
        save()
    }

    func displayName(for connection: ClusterConnection) -> String {
        customizations[connection.id]?.displayName ?? connection.name
    }

    func color(for clusterId: String) -> Color {
        get(for: clusterId).color
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let dict = try? JSONDecoder().decode([String: ClusterCustomization].self, from: data) else {
            return
        }
        customizations = dict
    }

    private func save() {
        if let data = try? JSONEncoder().encode(customizations) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
