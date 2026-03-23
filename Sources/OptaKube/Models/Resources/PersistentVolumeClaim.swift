import Foundation

struct PersistentVolumeClaim: K8sResource {
    var apiVersion: String?
    var kind: String?
    var metadata: ObjectMeta
    var spec: PersistentVolumeClaimSpec?
    var status: PersistentVolumeClaimStatus?

    var phase: String {
        status?.phase ?? "Unknown"
    }

    var volumeName: String {
        spec?.volumeName ?? ""
    }

    var capacity: String {
        status?.capacity?["storage"] ?? ""
    }

    var accessModesDisplay: String {
        spec?.accessModes?.joined(separator: ", ") ?? ""
    }

    var storageClassName: String {
        spec?.storageClassName ?? ""
    }

    var resourceStatus: ResourceStatus {
        switch phase {
        case "Bound": return .running
        case "Pending": return .pending
        case "Lost": return .failed
        default: return .unknown
        }
    }
}

struct PersistentVolumeClaimSpec: Codable, Sendable {
    var accessModes: [String]?
    var storageClassName: String?
    var volumeName: String?
    var resources: PVCResourceRequirements?
}

struct PVCResourceRequirements: Codable, Sendable {
    var requests: [String: String]?
    var limits: [String: String]?
}

struct PersistentVolumeClaimStatus: Codable, Sendable {
    var phase: String?
    var capacity: [String: String]?
    var accessModes: [String]?
}
