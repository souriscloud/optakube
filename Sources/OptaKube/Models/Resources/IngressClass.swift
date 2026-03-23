import Foundation

struct IngressClass: K8sResource {
    var apiVersion: String?
    var kind: String?
    var metadata: ObjectMeta
    var spec: IngressClassSpec?

    var controller: String { spec?.controller ?? "" }

    var isDefault: Bool {
        metadata.annotations?["ingressclass.kubernetes.io/is-default-class"] == "true"
    }

    var resourceStatus: ResourceStatus {
        return .running
    }
}

struct IngressClassSpec: Codable, Sendable {
    var controller: String?
    var parameters: IngressClassParametersReference?
}

struct IngressClassParametersReference: Codable, Sendable {
    var apiGroup: String?
    var kind: String?
    var name: String?
}
