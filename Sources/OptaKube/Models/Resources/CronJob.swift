import Foundation

struct CronJob: K8sResource {
    var apiVersion: String?
    var kind: String?
    var metadata: ObjectMeta
    var spec: CronJobSpec?
    var status: CronJobStatus?

    var schedule: String { spec?.schedule ?? "" }
    var isSuspended: Bool { spec?.suspend ?? false }

    var lastScheduleDisplay: String {
        guard let last = status?.lastScheduleTime else { return "Never" }
        let interval = Date().timeIntervalSince(last)
        if interval < 60 { return "\(Int(interval))s ago" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        return "\(Int(interval / 86400))d ago"
    }

    var resourceStatus: ResourceStatus {
        if isSuspended { return .pending }
        if (status?.active?.count ?? 0) > 0 { return .running }
        return .succeeded
    }
}

struct CronJobSpec: Codable, Sendable {
    var schedule: String?
    var suspend: Bool?
    var concurrencyPolicy: String?
    var jobTemplate: JobTemplateSpec?
}

struct JobTemplateSpec: Codable, Sendable {
    var metadata: ObjectMeta?
    var spec: JobSpec?
}

struct CronJobStatus: Codable, Sendable {
    var active: [CronJobActiveRef]?
    var lastScheduleTime: Date?
    var lastSuccessfulTime: Date?
}

struct CronJobActiveRef: Codable, Sendable {
    var name: String?
    var namespace: String?
    var uid: String?
}
