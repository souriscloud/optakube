import Foundation

struct Deployment: K8sResource {
    var apiVersion: String?
    var kind: String?
    var metadata: ObjectMeta
    var spec: DeploymentSpec?
    var status: DeploymentStatus?

    var replicas: Int { spec?.replicas ?? 0 }
    var readyReplicas: Int { status?.readyReplicas ?? 0 }
    var updatedReplicas: Int { status?.updatedReplicas ?? 0 }
    var availableReplicas: Int { status?.availableReplicas ?? 0 }

    var resourceStatus: ResourceStatus {
        if readyReplicas == replicas && replicas > 0 { return .running }
        if readyReplicas > 0 { return .warning }
        if replicas == 0 { return .pending }
        return .failed
    }
}

struct DeploymentSpec: Codable, Sendable {
    var replicas: Int?
    var selector: LabelSelector?
    var strategy: DeploymentStrategy?
    var template: PodTemplateSpec?
}

struct DeploymentStrategy: Codable, Sendable {
    var type: String?
    var rollingUpdate: RollingUpdateDeployment?
}

struct RollingUpdateDeployment: Codable, Sendable {
    var maxSurge: IntOrString?
    var maxUnavailable: IntOrString?
}

enum IntOrString: Codable, Sendable {
    case int(Int)
    case string(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intVal = try? container.decode(Int.self) {
            self = .int(intVal)
        } else if let strVal = try? container.decode(String.self) {
            self = .string(strVal)
        } else {
            throw DecodingError.typeMismatch(IntOrString.self, .init(codingPath: decoder.codingPath, debugDescription: "Expected Int or String"))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .int(let v): try container.encode(v)
        case .string(let v): try container.encode(v)
        }
    }

    var displayValue: String {
        switch self {
        case .int(let v): return "\(v)"
        case .string(let v): return v
        }
    }
}

struct LabelSelector: Codable, Sendable {
    var matchLabels: [String: String]?
}

struct PodTemplateSpec: Codable, Sendable {
    var metadata: ObjectMeta?
    var spec: PodSpec?
}

struct DeploymentStatus: Codable, Sendable {
    var observedGeneration: Int?
    var replicas: Int?
    var updatedReplicas: Int?
    var readyReplicas: Int?
    var availableReplicas: Int?
    var unavailableReplicas: Int?
    var conditions: [DeploymentCondition]?
}

struct DeploymentCondition: Codable, Sendable {
    var type: String
    var status: String
    var reason: String?
    var message: String?
    var lastUpdateTime: Date?
    var lastTransitionTime: Date?
}
