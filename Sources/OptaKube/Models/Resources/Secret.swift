import Foundation

struct Secret: K8sResource {
    var apiVersion: String?
    var kind: String?
    var metadata: ObjectMeta
    var data: [String: String]?
    var stringData: [String: String]?
    var type: String?

    var dataCount: Int { data?.count ?? 0 }
    var secretType: String { type ?? "Opaque" }
    var resourceStatus: ResourceStatus { .running }
}
