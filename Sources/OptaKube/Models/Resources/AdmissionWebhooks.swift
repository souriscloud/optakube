import Foundation

// MARK: - Admission Webhook Configurations (admissionregistration.k8s.io/v1)

struct MutatingWebhookConfiguration: K8sResource {
    var apiVersion: String?
    var kind: String?
    var metadata: ObjectMeta
    var webhooks: [AdmissionWebhook]?

    var webhookCount: Int { webhooks?.count ?? 0 }
    var webhookNames: String {
        let names = webhooks?.compactMap { $0.name } ?? []
        return names.isEmpty ? "—" : names.joined(separator: ", ")
    }

    var resourceStatus: ResourceStatus { .running }
}

struct ValidatingWebhookConfiguration: K8sResource {
    var apiVersion: String?
    var kind: String?
    var metadata: ObjectMeta
    var webhooks: [AdmissionWebhook]?

    var webhookCount: Int { webhooks?.count ?? 0 }
    var webhookNames: String {
        let names = webhooks?.compactMap { $0.name } ?? []
        return names.isEmpty ? "—" : names.joined(separator: ", ")
    }

    var resourceStatus: ResourceStatus { .running }
}

struct AdmissionWebhook: Codable, Sendable {
    var name: String?
}
