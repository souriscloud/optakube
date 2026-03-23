import Foundation

struct Namespace: K8sResource {
    var apiVersion: String?
    var kind: String?
    var metadata: ObjectMeta
    var status: NamespaceStatus?

    var phase: String {
        status?.phase ?? "Unknown"
    }

    var resourceStatus: ResourceStatus {
        switch phase {
        case "Active": return .running
        case "Terminating": return .warning
        default: return .unknown
        }
    }
}

struct NamespaceStatus: Codable, Sendable {
    var phase: String?
}
