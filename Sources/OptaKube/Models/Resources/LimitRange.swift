import Foundation

// MARK: - LimitRange (core/v1)

struct LimitRange: K8sResource {
    var apiVersion: String?
    var kind: String?
    var metadata: ObjectMeta
    var spec: LimitRangeSpec?

    var limitTypes: String {
        let types = spec?.limits?.compactMap { $0.type } ?? []
        return types.isEmpty ? "—" : types.joined(separator: ", ")
    }

    var limitsCount: Int { spec?.limits?.count ?? 0 }

    var resourceStatus: ResourceStatus { .running }
}

struct LimitRangeSpec: Codable, Sendable {
    var limits: [LimitRangeItem]?
}

struct LimitRangeItem: Codable, Sendable {
    var type: String?
    var max: [String: String]?
    var min: [String: String]?
    var `default`: [String: String]?
    var defaultRequest: [String: String]?
}
