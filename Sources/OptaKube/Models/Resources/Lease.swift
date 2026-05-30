import Foundation

// MARK: - Lease (coordination.k8s.io/v1)

struct Lease: K8sResource {
    var apiVersion: String?
    var kind: String?
    var metadata: ObjectMeta
    var spec: LeaseSpec?

    var holder: String { spec?.holderIdentity ?? "—" }
    var durationDisplay: String { spec?.leaseDurationSeconds.map { "\($0)s" } ?? "—" }
    var renewTime: String { spec?.renewTime ?? "" }

    var resourceStatus: ResourceStatus { .running }
}

struct LeaseSpec: Codable, Sendable {
    var holderIdentity: String?
    var leaseDurationSeconds: Int?
    var renewTime: String?
    var acquireTime: String?
}
