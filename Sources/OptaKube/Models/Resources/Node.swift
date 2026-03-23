import Foundation

struct Node: K8sResource {
    var apiVersion: String?
    var kind: String?
    var metadata: ObjectMeta
    var spec: NodeSpec?
    var status: NodeStatus?

    var roles: String {
        metadata.labels?.compactMap { key, _ in
            if key.hasPrefix("node-role.kubernetes.io/") {
                return String(key.dropFirst("node-role.kubernetes.io/".count))
            }
            return nil
        }.joined(separator: ", ") ?? ""
    }

    var kubeletVersion: String { status?.nodeInfo?.kubeletVersion ?? "" }

    var resourceStatus: ResourceStatus {
        let readyCondition = status?.conditions?.first { $0.type == "Ready" }
        if readyCondition?.status == "True" { return .running }
        return .failed
    }
}

struct NodeSpec: Codable, Sendable {
    var podCIDR: String?
    var taints: [Taint]?
    var unschedulable: Bool?
}

struct Taint: Codable, Sendable {
    var key: String
    var value: String?
    var effect: String
}

struct NodeStatus: Codable, Sendable {
    var conditions: [NodeCondition]?
    var addresses: [NodeAddress]?
    var capacity: [String: String]?
    var allocatable: [String: String]?
    var nodeInfo: NodeSystemInfo?
}

struct NodeCondition: Codable, Sendable {
    var type: String
    var status: String
    var reason: String?
    var message: String?
    var lastHeartbeatTime: Date?
    var lastTransitionTime: Date?
}

struct NodeAddress: Codable, Sendable {
    var type: String
    var address: String
}

struct NodeSystemInfo: Codable, Sendable {
    var machineID: String?
    var systemUUID: String?
    var bootID: String?
    var kernelVersion: String?
    var osImage: String?
    var containerRuntimeVersion: String?
    var kubeletVersion: String?
    var kubeProxyVersion: String?
    var operatingSystem: String?
    var architecture: String?
}
