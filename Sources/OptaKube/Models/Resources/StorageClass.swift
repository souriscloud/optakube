import Foundation

// MARK: - StorageClass (storage.k8s.io/v1)

struct StorageClass: K8sResource {
    var apiVersion: String?
    var kind: String?
    var metadata: ObjectMeta
    var provisioner: String?
    var reclaimPolicy: String?
    var volumeBindingMode: String?
    var allowVolumeExpansion: Bool?

    /// kubectl marks the default class via this annotation.
    var isDefault: Bool {
        metadata.annotations?["storageclass.kubernetes.io/is-default-class"] == "true"
    }

    var reclaimPolicyDisplay: String { reclaimPolicy ?? "Delete" }
    var bindingModeDisplay: String { volumeBindingMode ?? "Immediate" }

    var resourceStatus: ResourceStatus { .running }
}
