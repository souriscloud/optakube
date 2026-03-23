import Foundation

struct ConfigMap: K8sResource {
    var apiVersion: String?
    var kind: String?
    var metadata: ObjectMeta
    var data: [String: String]?
    var binaryData: [String: String]?

    var dataCount: Int { (data?.count ?? 0) + (binaryData?.count ?? 0) }
    var resourceStatus: ResourceStatus { .running }
}
