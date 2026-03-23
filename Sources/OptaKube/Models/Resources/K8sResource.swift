import Foundation

protocol K8sResource: Codable, Identifiable, Sendable {
    var metadata: ObjectMeta { get }
}

extension K8sResource {
    var id: String {
        "\(metadata.namespace ?? "")/\(metadata.name ?? "unknown")"
    }

    var name: String { metadata.name ?? "unknown" }
    var namespace: String { metadata.namespace ?? "default" }
    var creationTimestamp: Date? { metadata.creationTimestamp }

    var age: String {
        guard let created = metadata.creationTimestamp else { return "?" }
        let interval = Date().timeIntervalSince(created)
        if interval < 60 { return "\(Int(interval))s" }
        if interval < 3600 { return "\(Int(interval / 60))m" }
        if interval < 86400 { return "\(Int(interval / 3600))h" }
        return "\(Int(interval / 86400))d"
    }
}

struct ObjectMeta: Codable, Sendable {
    var name: String?
    var namespace: String?
    var uid: String?
    var resourceVersion: String?
    var creationTimestamp: Date?
    var labels: [String: String]?
    var annotations: [String: String]?
    var ownerReferences: [OwnerReference]?
}

struct OwnerReference: Codable, Sendable {
    var apiVersion: String
    var kind: String
    var name: String
    var uid: String
}

struct K8sListResponse<T: Codable>: Codable {
    var apiVersion: String?
    var kind: String?
    var metadata: ListMeta?
    var items: [T]

    struct ListMeta: Codable {
        var resourceVersion: String?
        var `continue`: String?
    }
}
