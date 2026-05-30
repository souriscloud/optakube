import SwiftUI

enum ResourceCategory: String, CaseIterable {
    case workloads = "Workloads"
    case networking = "Networking"
    case config = "Config & Storage"
    case cluster = "Cluster"
}

enum ResourceType: String, CaseIterable, Identifiable, Hashable {
    case pods
    case deployments
    case statefulSets
    case daemonSets
    case replicaSets
    case jobs
    case cronJobs
    case services
    case ingresses
    case ingressClasses
    case networkPolicies
    case endpoints
    case configMaps
    case secrets
    case persistentVolumes
    case persistentVolumeClaims
    case nodes
    case serviceAccounts
    case horizontalPodAutoscalers
    case namespaces
    case roles
    case roleBindings
    case clusterRoles
    case clusterRoleBindings
    case storageClasses
    case resourceQuotas
    case podDisruptionBudgets
    case limitRanges
    case priorityClasses
    case leases
    case mutatingWebhookConfigurations
    case validatingWebhookConfigurations

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pods: return "Pods"
        case .deployments: return "Deployments"
        case .statefulSets: return "StatefulSets"
        case .daemonSets: return "DaemonSets"
        case .replicaSets: return "ReplicaSets"
        case .jobs: return "Jobs"
        case .cronJobs: return "CronJobs"
        case .services: return "Services"
        case .ingresses: return "Ingresses"
        case .ingressClasses: return "IngressClasses"
        case .networkPolicies: return "NetworkPolicies"
        case .endpoints: return "Endpoints"
        case .configMaps: return "ConfigMaps"
        case .secrets: return "Secrets"
        case .persistentVolumes: return "PersistentVolumes"
        case .persistentVolumeClaims: return "PersistentVolumeClaims"
        case .nodes: return "Nodes"
        case .serviceAccounts: return "ServiceAccounts"
        case .horizontalPodAutoscalers: return "HorizontalPodAutoscalers"
        case .namespaces: return "Namespaces"
        case .roles: return "Roles"
        case .roleBindings: return "RoleBindings"
        case .clusterRoles: return "ClusterRoles"
        case .clusterRoleBindings: return "ClusterRoleBindings"
        case .storageClasses: return "StorageClasses"
        case .resourceQuotas: return "ResourceQuotas"
        case .podDisruptionBudgets: return "PodDisruptionBudgets"
        case .limitRanges: return "LimitRanges"
        case .priorityClasses: return "PriorityClasses"
        case .leases: return "Leases"
        case .mutatingWebhookConfigurations: return "MutatingWebhookConfigurations"
        case .validatingWebhookConfigurations: return "ValidatingWebhookConfigurations"
        }
    }

    var systemImage: String {
        switch self {
        case .pods: return "cube"
        case .deployments: return "arrow.triangle.2.circlepath"
        case .statefulSets: return "square.stack.3d.up"
        case .daemonSets: return "circle.grid.3x3"
        case .replicaSets: return "square.on.square"
        case .jobs: return "bolt"
        case .cronJobs: return "clock"
        case .services: return "network"
        case .ingresses: return "arrow.right.arrow.left"
        case .ingressClasses: return "shield.lefthalf.filled"
        case .networkPolicies: return "lock.shield"
        case .endpoints: return "point.3.connected.trianglepath.dotted"
        case .configMaps: return "doc.text"
        case .secrets: return "lock"
        case .persistentVolumes: return "externaldrive"
        case .persistentVolumeClaims: return "externaldrive.badge.checkmark"
        case .nodes: return "desktopcomputer"
        case .serviceAccounts: return "person.crop.circle"
        case .horizontalPodAutoscalers: return "arrow.up.arrow.down"
        case .namespaces: return "folder"
        case .roles: return "shield.lefthalf.filled"
        case .roleBindings: return "link.circle"
        case .clusterRoles: return "shield"
        case .clusterRoleBindings: return "link.circle.fill"
        case .storageClasses: return "internaldrive"
        case .resourceQuotas: return "slider.horizontal.3"
        case .podDisruptionBudgets: return "bolt.shield"
        case .limitRanges: return "ruler"
        case .priorityClasses: return "arrow.up.arrow.down.square"
        case .leases: return "clock.arrow.circlepath"
        case .mutatingWebhookConfigurations: return "arrow.triangle.branch"
        case .validatingWebhookConfigurations: return "checkmark.shield"
        }
    }

    var category: ResourceCategory {
        switch self {
        case .pods, .deployments, .statefulSets, .daemonSets, .replicaSets, .jobs, .cronJobs:
            return .workloads
        case .services, .ingresses, .ingressClasses, .networkPolicies, .endpoints:
            return .networking
        case .configMaps, .secrets, .persistentVolumes, .persistentVolumeClaims,
             .resourceQuotas, .podDisruptionBudgets, .limitRanges:
            return .config
        case .nodes, .serviceAccounts, .horizontalPodAutoscalers, .namespaces,
             .roles, .roleBindings, .clusterRoles, .clusterRoleBindings, .storageClasses,
             .priorityClasses, .leases, .mutatingWebhookConfigurations, .validatingWebhookConfigurations:
            return .cluster
        }
    }

    var apiGroup: String {
        switch self {
        case .pods, .services, .configMaps, .secrets, .nodes, .persistentVolumes, .persistentVolumeClaims, .serviceAccounts, .namespaces, .endpoints:
            return "/api/v1"
        case .deployments, .statefulSets, .daemonSets, .replicaSets:
            return "/apis/apps/v1"
        case .jobs, .cronJobs:
            return "/apis/batch/v1"
        case .ingresses, .ingressClasses, .networkPolicies:
            return "/apis/networking.k8s.io/v1"
        case .horizontalPodAutoscalers:
            return "/apis/autoscaling/v2"
        case .roles, .roleBindings, .clusterRoles, .clusterRoleBindings:
            return "/apis/rbac.authorization.k8s.io/v1"
        case .storageClasses:
            return "/apis/storage.k8s.io/v1"
        case .resourceQuotas:
            return "/api/v1"
        case .podDisruptionBudgets:
            return "/apis/policy/v1"
        case .limitRanges:
            return "/api/v1"
        case .priorityClasses:
            return "/apis/scheduling.k8s.io/v1"
        case .leases:
            return "/apis/coordination.k8s.io/v1"
        case .mutatingWebhookConfigurations, .validatingWebhookConfigurations:
            return "/apis/admissionregistration.k8s.io/v1"
        }
    }

    var resource: String {
        switch self {
        case .pods: return "pods"
        case .deployments: return "deployments"
        case .statefulSets: return "statefulsets"
        case .daemonSets: return "daemonsets"
        case .replicaSets: return "replicasets"
        case .jobs: return "jobs"
        case .cronJobs: return "cronjobs"
        case .services: return "services"
        case .ingresses: return "ingresses"
        case .ingressClasses: return "ingressclasses"
        case .networkPolicies: return "networkpolicies"
        case .endpoints: return "endpoints"
        case .configMaps: return "configmaps"
        case .secrets: return "secrets"
        case .persistentVolumes: return "persistentvolumes"
        case .persistentVolumeClaims: return "persistentvolumeclaims"
        case .nodes: return "nodes"
        case .serviceAccounts: return "serviceaccounts"
        case .horizontalPodAutoscalers: return "horizontalpodautoscalers"
        case .namespaces: return "namespaces"
        case .roles: return "roles"
        case .roleBindings: return "rolebindings"
        case .clusterRoles: return "clusterroles"
        case .clusterRoleBindings: return "clusterrolebindings"
        case .storageClasses: return "storageclasses"
        case .resourceQuotas: return "resourcequotas"
        case .podDisruptionBudgets: return "poddisruptionbudgets"
        case .limitRanges: return "limitranges"
        case .priorityClasses: return "priorityclasses"
        case .leases: return "leases"
        case .mutatingWebhookConfigurations: return "mutatingwebhookconfigurations"
        case .validatingWebhookConfigurations: return "validatingwebhookconfigurations"
        }
    }

    var isNamespaced: Bool {
        switch self {
        case .nodes, .persistentVolumes, .ingressClasses, .namespaces,
             .clusterRoles, .clusterRoleBindings, .storageClasses,
             .priorityClasses, .mutatingWebhookConfigurations, .validatingWebhookConfigurations:
            return false
        default:
            return true
        }
    }

    /// The singular Kubernetes Kind (PascalCase), as it appears in a manifest's
    /// `kind:` field. Used to resolve a pasted manifest back to its resource path.
    var kind: String {
        switch self {
        case .pods: return "Pod"
        case .deployments: return "Deployment"
        case .statefulSets: return "StatefulSet"
        case .daemonSets: return "DaemonSet"
        case .replicaSets: return "ReplicaSet"
        case .jobs: return "Job"
        case .cronJobs: return "CronJob"
        case .services: return "Service"
        case .ingresses: return "Ingress"
        case .ingressClasses: return "IngressClass"
        case .networkPolicies: return "NetworkPolicy"
        case .endpoints: return "Endpoints"
        case .configMaps: return "ConfigMap"
        case .secrets: return "Secret"
        case .persistentVolumes: return "PersistentVolume"
        case .persistentVolumeClaims: return "PersistentVolumeClaim"
        case .nodes: return "Node"
        case .serviceAccounts: return "ServiceAccount"
        case .horizontalPodAutoscalers: return "HorizontalPodAutoscaler"
        case .namespaces: return "Namespace"
        case .roles: return "Role"
        case .roleBindings: return "RoleBinding"
        case .clusterRoles: return "ClusterRole"
        case .clusterRoleBindings: return "ClusterRoleBinding"
        case .storageClasses: return "StorageClass"
        case .resourceQuotas: return "ResourceQuota"
        case .podDisruptionBudgets: return "PodDisruptionBudget"
        case .limitRanges: return "LimitRange"
        case .priorityClasses: return "PriorityClass"
        case .leases: return "Lease"
        case .mutatingWebhookConfigurations: return "MutatingWebhookConfiguration"
        case .validatingWebhookConfigurations: return "ValidatingWebhookConfiguration"
        }
    }

    /// The bare API group name (no version), as the authorization API expects it:
    /// `""` for core (`/api/v1`), otherwise the group from `/apis/<group>/<version>`.
    /// e.g. `.deployments` → `"apps"`, `.pods` → `""`, `.ingresses` → `"networking.k8s.io"`.
    var apiGroupName: String {
        // apiGroup is "/api/v1" (core) or "/apis/<group>/<version>".
        let parts = apiGroup.split(separator: "/").map(String.init)
        // ["api", "v1"] → core; ["apis", "apps", "v1"] → "apps"
        if parts.first == "apis", parts.count >= 2 {
            return parts[1]
        }
        return ""
    }

    func listURL(server: String, namespace: String?) -> URL? {
        var path: String
        if isNamespaced, let ns = namespace {
            path = "\(apiGroup)/namespaces/\(ns)/\(resource)"
        } else if isNamespaced {
            path = "\(apiGroup)/\(resource)"
        } else {
            path = "\(apiGroup)/\(resource)"
        }
        return URL(string: server + path)
    }

    static var grouped: [(ResourceCategory, [ResourceType])] {
        ResourceCategory.allCases.map { category in
            (category, ResourceType.allCases.filter { $0.category == category })
        }
    }
}
