import Foundation

struct PersistentVolume: K8sResource {
    var apiVersion: String?
    var kind: String?
    var metadata: ObjectMeta
    var spec: PersistentVolumeSpec?
    var status: PersistentVolumeStatus?

    var capacity: String {
        spec?.capacity?["storage"] ?? ""
    }

    var accessModesDisplay: String {
        spec?.accessModes?.joined(separator: ", ") ?? ""
    }

    var reclaimPolicy: String {
        spec?.persistentVolumeReclaimPolicy ?? ""
    }

    var phase: String {
        status?.phase ?? "Unknown"
    }

    var storageClassName: String {
        spec?.storageClassName ?? ""
    }

    var resourceStatus: ResourceStatus {
        switch phase {
        case "Available": return .running
        case "Bound": return .running
        case "Released": return .warning
        case "Failed": return .failed
        default: return .unknown
        }
    }
}

struct PersistentVolumeSpec: Codable, Sendable {
    var capacity: [String: String]?
    var accessModes: [String]?
    var persistentVolumeReclaimPolicy: String?
    var storageClassName: String?
    var claimRef: PVClaimRef?
}

struct PVClaimRef: Codable, Sendable {
    var name: String?
    var namespace: String?
}

struct PersistentVolumeStatus: Codable, Sendable {
    var phase: String?
}
