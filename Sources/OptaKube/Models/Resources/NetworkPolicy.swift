import Foundation

struct NetworkPolicy: K8sResource {
    var apiVersion: String?
    var kind: String?
    var metadata: ObjectMeta
    var spec: NetworkPolicySpec?

    var podSelectorDisplay: String {
        guard let matchLabels = spec?.podSelector?.matchLabels, !matchLabels.isEmpty else {
            return "(all pods)"
        }
        return matchLabels.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
    }

    var policyTypesDisplay: String {
        spec?.policyTypes?.joined(separator: ", ") ?? ""
    }

    var resourceStatus: ResourceStatus {
        return .running
    }
}

struct NetworkPolicySpec: Codable, Sendable {
    var podSelector: LabelSelector?
    var policyTypes: [String]?
    var ingress: [NetworkPolicyIngressRule]?
    var egress: [NetworkPolicyEgressRule]?
}

struct NetworkPolicyIngressRule: Codable, Sendable {
    var from: [NetworkPolicyPeer]?
    var ports: [NetworkPolicyPort]?
}

struct NetworkPolicyEgressRule: Codable, Sendable {
    var to: [NetworkPolicyPeer]?
    var ports: [NetworkPolicyPort]?
}

struct NetworkPolicyPeer: Codable, Sendable {
    var podSelector: LabelSelector?
    var namespaceSelector: LabelSelector?
}

struct NetworkPolicyPort: Codable, Sendable {
    var port: IntOrString?
    var `protocol`: String?
}
