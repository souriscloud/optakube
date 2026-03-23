import Foundation

struct Ingress: K8sResource {
    var apiVersion: String?
    var kind: String?
    var metadata: ObjectMeta
    var spec: IngressSpec?
    var status: IngressResourceStatus?

    var ingressClassName: String { spec?.ingressClassName ?? "" }

    var hostsDisplay: String {
        spec?.rules?.compactMap { $0.host }.joined(separator: ", ") ?? ""
    }

    var pathsDisplay: String {
        let paths = spec?.rules?.flatMap { rule in
            rule.http?.paths?.map { $0.path ?? "/" } ?? []
        } ?? []
        return paths.joined(separator: ", ")
    }

    var backendServiceDisplay: String {
        if let defaultBackend = spec?.defaultBackend?.service {
            return "\(defaultBackend.name):\(defaultBackend.port?.number ?? 0)"
        }
        let services = spec?.rules?.flatMap { rule in
            rule.http?.paths?.compactMap { $0.backend?.service?.name } ?? []
        } ?? []
        return services.joined(separator: ", ")
    }

    var tlsEnabled: Bool {
        spec?.tls?.isEmpty == false
    }

    var resourceStatus: ResourceStatus {
        if status?.loadBalancer?.ingress?.isEmpty == false {
            return .running
        }
        return .pending
    }
}

struct IngressSpec: Codable, Sendable {
    var ingressClassName: String?
    var defaultBackend: IngressBackend?
    var rules: [IngressRule]?
    var tls: [IngressTLS]?
}

struct IngressRule: Codable, Sendable {
    var host: String?
    var http: HTTPIngressRuleValue?
}

struct HTTPIngressRuleValue: Codable, Sendable {
    var paths: [HTTPIngressPath]?
}

struct HTTPIngressPath: Codable, Sendable {
    var path: String?
    var pathType: String?
    var backend: IngressBackend?
}

struct IngressBackend: Codable, Sendable {
    var service: IngressServiceBackend?
}

struct IngressServiceBackend: Codable, Sendable {
    var name: String
    var port: IngressServiceBackendPort?
}

struct IngressServiceBackendPort: Codable, Sendable {
    var number: Int?
    var name: String?
}

struct IngressTLS: Codable, Sendable {
    var hosts: [String]?
    var secretName: String?
}

struct IngressResourceStatus: Codable, Sendable {
    var loadBalancer: LoadBalancerStatus?
}
