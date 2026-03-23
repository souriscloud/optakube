import Foundation

struct HorizontalPodAutoscaler: K8sResource {
    var apiVersion: String?
    var kind: String?
    var metadata: ObjectMeta
    var spec: HPASpec?
    var status: HPAStatus?

    var minReplicas: Int { spec?.minReplicas ?? 1 }
    var maxReplicas: Int { spec?.maxReplicas ?? 0 }
    var currentReplicas: Int { status?.currentReplicas ?? 0 }
    var desiredReplicas: Int { status?.desiredReplicas ?? 0 }

    var currentMetricsDisplay: String {
        guard let metrics = status?.currentMetrics, !metrics.isEmpty else { return "N/A" }
        return metrics.compactMap { metric in
            if let resource = metric.resource {
                return "\(resource.name): \(resource.current?.averageUtilization.map { "\($0)%" } ?? "?")"
            }
            return nil
        }.joined(separator: ", ")
    }

    var targetMetricsDisplay: String {
        guard let metrics = spec?.metrics, !metrics.isEmpty else { return "N/A" }
        return metrics.compactMap { metric in
            if let resource = metric.resource {
                return "\(resource.name): \(resource.target?.averageUtilization.map { "\($0)%" } ?? "?")"
            }
            return nil
        }.joined(separator: ", ")
    }

    var resourceStatus: ResourceStatus {
        if currentReplicas == desiredReplicas && currentReplicas > 0 {
            return .running
        }
        if currentReplicas == 0 {
            return .pending
        }
        return .warning
    }
}

struct HPASpec: Codable, Sendable {
    var minReplicas: Int?
    var maxReplicas: Int?
    var metrics: [HPAMetricSpec]?
    var scaleTargetRef: CrossVersionObjectReference?
}

struct CrossVersionObjectReference: Codable, Sendable {
    var apiVersion: String?
    var kind: String?
    var name: String?
}

struct HPAMetricSpec: Codable, Sendable {
    var type: String?
    var resource: HPAResourceMetricSource?
}

struct HPAResourceMetricSource: Codable, Sendable {
    var name: String
    var target: HPAMetricTarget?
}

struct HPAMetricTarget: Codable, Sendable {
    var type: String?
    var averageUtilization: Int?
    var averageValue: String?
}

struct HPAStatus: Codable, Sendable {
    var currentReplicas: Int?
    var desiredReplicas: Int?
    var currentMetrics: [HPAMetricStatus]?
}

struct HPAMetricStatus: Codable, Sendable {
    var type: String?
    var resource: HPAResourceMetricStatus?
}

struct HPAResourceMetricStatus: Codable, Sendable {
    var name: String
    var current: HPAMetricValueStatus?
}

struct HPAMetricValueStatus: Codable, Sendable {
    var averageUtilization: Int?
    var averageValue: String?
}
