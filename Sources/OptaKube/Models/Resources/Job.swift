import Foundation

struct Job: K8sResource {
    var apiVersion: String?
    var kind: String?
    var metadata: ObjectMeta
    var spec: JobSpec?
    var status: JobStatus?

    var completions: Int { spec?.completions ?? 1 }
    var succeeded: Int { status?.succeeded ?? 0 }

    var duration: String {
        guard let start = status?.startTime else { return "" }
        let end = status?.completionTime ?? Date()
        let interval = end.timeIntervalSince(start)
        if interval < 60 { return "\(Int(interval))s" }
        if interval < 3600 { return "\(Int(interval / 60))m" }
        return "\(Int(interval / 3600))h\(Int(interval.truncatingRemainder(dividingBy: 3600) / 60))m"
    }

    var resourceStatus: ResourceStatus {
        if let conditions = status?.conditions {
            if conditions.contains(where: { $0.type == "Complete" && $0.status == "True" }) {
                return .succeeded
            }
            if conditions.contains(where: { $0.type == "Failed" && $0.status == "True" }) {
                return .failed
            }
        }
        if (status?.active ?? 0) > 0 { return .running }
        return .pending
    }
}

struct JobSpec: Codable, Sendable {
    var completions: Int?
    var parallelism: Int?
    var backoffLimit: Int?
    var template: PodTemplateSpec?
}

struct JobStatus: Codable, Sendable {
    var conditions: [JobCondition]?
    var startTime: Date?
    var completionTime: Date?
    var active: Int?
    var succeeded: Int?
    var failed: Int?
}

struct JobCondition: Codable, Sendable {
    var type: String
    var status: String
    var reason: String?
    var message: String?
    var lastTransitionTime: Date?
}
