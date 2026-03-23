import Foundation

struct ServiceAccount: K8sResource {
    var apiVersion: String?
    var kind: String?
    var metadata: ObjectMeta
    var secrets: [SASecretReference]?

    var secretsCount: Int {
        secrets?.count ?? 0
    }

    var resourceStatus: ResourceStatus {
        return .running
    }
}

struct SASecretReference: Codable, Sendable {
    var name: String?
}
