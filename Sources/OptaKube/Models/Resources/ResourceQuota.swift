import Foundation

// MARK: - ResourceQuota (core/v1)

struct ResourceQuota: K8sResource {
    var apiVersion: String?
    var kind: String?
    var metadata: ObjectMeta
    var spec: ResourceQuotaSpec?
    var status: ResourceQuotaStatus?

    /// Compact "key=value, …" of the hard limits (sorted, capped for the table cell).
    var hardDisplay: String { Self.format(status?.hard ?? spec?.hard) }
    var usedDisplay: String { Self.format(status?.used) }

    private static func format(_ map: [String: String]?) -> String {
        guard let map, !map.isEmpty else { return "—" }
        let sorted = map.sorted { $0.key < $1.key }
        let shown = sorted.prefix(4).map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
        return sorted.count > 4 ? "\(shown), +\(sorted.count - 4)" : shown
    }

    var resourceStatus: ResourceStatus { .running }
}

struct ResourceQuotaSpec: Codable, Sendable {
    var hard: [String: String]?
}

struct ResourceQuotaStatus: Codable, Sendable {
    var hard: [String: String]?
    var used: [String: String]?
}
