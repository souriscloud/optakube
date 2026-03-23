import Foundation

struct ReplicaSet: K8sResource {
    var apiVersion: String?
    var kind: String?
    var metadata: ObjectMeta
    var spec: ReplicaSetSpec?
    var status: ReplicaSetStatus?

    var replicas: Int { spec?.replicas ?? 0 }
    var readyReplicas: Int { status?.readyReplicas ?? 0 }

    var resourceStatus: ResourceStatus {
        if readyReplicas == replicas && replicas > 0 { return .running }
        if readyReplicas > 0 { return .warning }
        if replicas == 0 { return .pending }
        return .failed
    }
}

struct ReplicaSetSpec: Codable, Sendable {
    var replicas: Int?
    var selector: LabelSelector?
    var template: PodTemplateSpec?
}

struct ReplicaSetStatus: Codable, Sendable {
    var replicas: Int?
    var readyReplicas: Int?
    var availableReplicas: Int?
}
