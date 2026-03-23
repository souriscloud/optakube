import Foundation

struct Endpoints: K8sResource {
    var apiVersion: String?
    var kind: String?
    var metadata: ObjectMeta
    var subsets: [EndpointSubset]?

    var addressCount: Int {
        subsets?.reduce(0) { $0 + ($1.addresses?.count ?? 0) } ?? 0
    }

    var portsDisplay: String {
        let ports = subsets?.flatMap { $0.ports ?? [] } ?? []
        return ports.map { p in
            let name = p.name.map { "\($0):" } ?? ""
            return "\(name)\(p.port)/\(p.protocol ?? "TCP")"
        }.joined(separator: ", ")
    }

    var resourceStatus: ResourceStatus {
        if addressCount > 0 {
            return .running
        }
        return .warning
    }
}

struct EndpointSubset: Codable, Sendable {
    var addresses: [EndpointAddress]?
    var notReadyAddresses: [EndpointAddress]?
    var ports: [EndpointPort]?
}

struct EndpointAddress: Codable, Sendable {
    var ip: String?
    var hostname: String?
    var nodeName: String?
}

struct EndpointPort: Codable, Sendable {
    var name: String?
    var port: Int
    var `protocol`: String?
}
