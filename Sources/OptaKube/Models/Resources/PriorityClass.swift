import Foundation

// MARK: - PriorityClass (scheduling.k8s.io/v1)

struct PriorityClass: K8sResource {
    var apiVersion: String?
    var kind: String?
    var metadata: ObjectMeta
    var value: Int?
    var globalDefault: Bool?
    var preemptionPolicy: String?
    var description: String?

    var valueDisplay: String { value.map { "\($0)" } ?? "—" }
    var isGlobalDefault: Bool { globalDefault ?? false }

    var resourceStatus: ResourceStatus { .running }
}
