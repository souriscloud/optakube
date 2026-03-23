import Foundation

struct StatefulSet: K8sResource {
    var apiVersion: String?
    var kind: String?
    var metadata: ObjectMeta
    var spec: StatefulSetSpec?
    var status: StatefulSetStatus?

    var replicas: Int { spec?.replicas ?? 0 }
    var readyReplicas: Int { status?.readyReplicas ?? 0 }

    var resourceStatus: ResourceStatus {
        if readyReplicas == replicas && replicas > 0 { return .running }
        if readyReplicas > 0 { return .warning }
        if replicas == 0 { return .pending }
        return .failed
    }
}

struct StatefulSetSpec: Codable, Sendable {
    var replicas: Int?
    var selector: LabelSelector?
    var serviceName: String?
    var template: PodTemplateSpec?
}

struct StatefulSetStatus: Codable, Sendable {
    var replicas: Int?
    var readyReplicas: Int?
    var currentReplicas: Int?
    var updatedReplicas: Int?
}
