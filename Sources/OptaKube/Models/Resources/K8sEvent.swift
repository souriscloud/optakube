import Foundation

struct K8sEvent: K8sResource {
    var apiVersion: String?
    var kind: String?
    var metadata: ObjectMeta
    var involvedObject: K8sObjectReference?
    var reason: String?
    var message: String?
    var source: EventSource?
    var firstTimestamp: Date?
    var lastTimestamp: Date?
    var count: Int?
    var type: String?

    var resourceStatus: ResourceStatus {
        switch type {
        case "Warning": return .warning
        case "Normal": return .running
        default: return .unknown
        }
    }

    var ageDisplay: String {
        guard let ts = lastTimestamp ?? firstTimestamp ?? metadata.creationTimestamp else { return "?" }
        let interval = Date().timeIntervalSince(ts)
        if interval < 60 { return "\(Int(interval))s" }
        if interval < 3600 { return "\(Int(interval / 60))m" }
        if interval < 86400 { return "\(Int(interval / 3600))h" }
        return "\(Int(interval / 86400))d"
    }
}

struct K8sObjectReference: Codable, Sendable {
    var kind: String?
    var namespace: String?
    var name: String?
    var uid: String?
    var apiVersion: String?
    var fieldPath: String?
}

struct EventSource: Codable, Sendable {
    var component: String?
    var host: String?
}
