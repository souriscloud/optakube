import Foundation

struct Service: K8sResource {
    var apiVersion: String?
    var kind: String?
    var metadata: ObjectMeta
    var spec: ServiceSpec?
    var status: ServiceStatus?

    var serviceType: String { spec?.type ?? "ClusterIP" }
    var clusterIP: String { spec?.clusterIP ?? "" }

    var portsDisplay: String {
        spec?.ports?.map { p in
            let name = p.name.map { "\($0):" } ?? ""
            let nodePort = p.nodePort.map { ":\($0)" } ?? ""
            return "\(name)\(p.port)\(nodePort)/\(p.protocol ?? "TCP")"
        }.joined(separator: ", ") ?? ""
    }

    var resourceStatus: ResourceStatus {
        if serviceType == "LoadBalancer" {
            if status?.loadBalancer?.ingress?.isEmpty == false {
                return .running
            }
            return .pending
        }
        return .running
    }
}

struct ServiceSpec: Codable, Sendable {
    var type: String?
    var clusterIP: String?
    var ports: [ServicePort]?
    var selector: [String: String]?
    var externalIPs: [String]?
    var loadBalancerIP: String?
}

struct ServicePort: Codable, Sendable {
    var name: String?
    var port: Int
    var targetPort: IntOrString?
    var nodePort: Int?
    var `protocol`: String?
}

struct ServiceStatus: Codable, Sendable {
    var loadBalancer: LoadBalancerStatus?
}

struct LoadBalancerStatus: Codable, Sendable {
    var ingress: [LoadBalancerIngress]?
}

struct LoadBalancerIngress: Codable, Sendable {
    var ip: String?
    var hostname: String?
}
