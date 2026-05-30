import Foundation

// MARK: - RBAC: Roles & Bindings (rbac.authorization.k8s.io/v1)

/// A single permission rule. Shared by Role and ClusterRole.
struct PolicyRule: Codable, Sendable {
    var apiGroups: [String]?
    var resources: [String]?
    var verbs: [String]?
    var resourceNames: [String]?
    var nonResourceURLs: [String]?
}

/// What a binding points at (a Role or ClusterRole).
struct RoleRef: Codable, Sendable {
    var apiGroup: String?
    var kind: String?
    var name: String?
}

/// Who a binding grants to (User, Group, or ServiceAccount).
struct RBACSubject: Codable, Sendable {
    var kind: String?
    var name: String?
    var namespace: String?
}

struct Role: K8sResource {
    var apiVersion: String?
    var kind: String?
    var metadata: ObjectMeta
    var rules: [PolicyRule]?

    var rulesCount: Int { rules?.count ?? 0 }

    /// Distinct verbs across all rules, for an at-a-glance summary.
    var verbsSummary: String {
        let verbs = Set(rules?.flatMap { $0.verbs ?? [] } ?? [])
        if verbs.contains("*") { return "*" }
        return verbs.sorted().joined(separator: ", ")
    }

    var resourceStatus: ResourceStatus { .running }
}

struct ClusterRole: K8sResource {
    var apiVersion: String?
    var kind: String?
    var metadata: ObjectMeta
    var rules: [PolicyRule]?

    var rulesCount: Int { rules?.count ?? 0 }

    var verbsSummary: String {
        let verbs = Set(rules?.flatMap { $0.verbs ?? [] } ?? [])
        if verbs.contains("*") { return "*" }
        return verbs.sorted().joined(separator: ", ")
    }

    var resourceStatus: ResourceStatus { .running }
}

struct RoleBinding: K8sResource {
    var apiVersion: String?
    var kind: String?
    var metadata: ObjectMeta
    var roleRef: RoleRef?
    var subjects: [RBACSubject]?

    var roleRefDisplay: String {
        guard let ref = roleRef else { return "—" }
        return "\(ref.kind ?? "?")/\(ref.name ?? "?")"
    }

    var subjectsDisplay: String {
        let subs = subjects ?? []
        if subs.isEmpty { return "—" }
        return subs.map { "\($0.kind ?? "?"):\($0.name ?? "?")" }.joined(separator: ", ")
    }

    var resourceStatus: ResourceStatus { .running }
}

struct ClusterRoleBinding: K8sResource {
    var apiVersion: String?
    var kind: String?
    var metadata: ObjectMeta
    var roleRef: RoleRef?
    var subjects: [RBACSubject]?

    var roleRefDisplay: String {
        guard let ref = roleRef else { return "—" }
        return "\(ref.kind ?? "?")/\(ref.name ?? "?")"
    }

    var subjectsDisplay: String {
        let subs = subjects ?? []
        if subs.isEmpty { return "—" }
        return subs.map { "\($0.kind ?? "?"):\($0.name ?? "?")" }.joined(separator: ", ")
    }

    var resourceStatus: ResourceStatus { .running }
}
