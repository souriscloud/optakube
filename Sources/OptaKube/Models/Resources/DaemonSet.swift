import Foundation

struct DaemonSet: K8sResource {
    var apiVersion: String?
    var kind: String?
    var metadata: ObjectMeta
    var spec: DaemonSetSpec?
    var status: DaemonSetStatus?

    var desiredNumberScheduled: Int { status?.desiredNumberScheduled ?? 0 }
    var numberReady: Int { status?.numberReady ?? 0 }

    var resourceStatus: ResourceStatus {
        if numberReady == desiredNumberScheduled && desiredNumberScheduled > 0 { return .running }
        if numberReady > 0 { return .warning }
        return .failed
    }
}

struct DaemonSetSpec: Codable, Sendable {
    var selector: LabelSelector?
    var template: PodTemplateSpec?
}

struct DaemonSetStatus: Codable, Sendable {
    var desiredNumberScheduled: Int?
    var currentNumberScheduled: Int?
    var numberReady: Int?
    var numberAvailable: Int?
    var numberMisscheduled: Int?
}
