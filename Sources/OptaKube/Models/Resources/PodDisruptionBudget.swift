import Foundation

// MARK: - PodDisruptionBudget (policy/v1)

struct PodDisruptionBudget: K8sResource {
    var apiVersion: String?
    var kind: String?
    var metadata: ObjectMeta
    var spec: PDBSpec?
    var status: PDBStatus?

    var minAvailableDisplay: String { spec?.minAvailable?.displayValue ?? "—" }
    var maxUnavailableDisplay: String { spec?.maxUnavailable?.displayValue ?? "—" }

    var allowedDisruptions: Int { status?.disruptionsAllowed ?? 0 }
    var currentHealthy: Int { status?.currentHealthy ?? 0 }
    var desiredHealthy: Int { status?.desiredHealthy ?? 0 }

    var healthyDisplay: String { "\(currentHealthy)/\(desiredHealthy)" }

    /// Healthy when at least the desired number of pods are healthy; otherwise warn.
    var resourceStatus: ResourceStatus {
        guard status != nil else { return .unknown }
        return currentHealthy >= desiredHealthy ? .running : .warning
    }
}

struct PDBSpec: Codable, Sendable {
    var minAvailable: IntOrString?
    var maxUnavailable: IntOrString?
}

struct PDBStatus: Codable, Sendable {
    var currentHealthy: Int?
    var desiredHealthy: Int?
    var disruptionsAllowed: Int?
    var expectedPods: Int?
}
