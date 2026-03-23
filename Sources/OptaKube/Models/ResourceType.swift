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
        }
    }

    var category: ResourceCategory {
        switch self {
        case .pods, .deployments, .statefulSets, .daemonSets, .replicaSets, .jobs, .cronJobs:
            return .workloads
        case .services, .ingresses, .ingressClasses, .networkPolicies, .endpoints:
            return .networking
        case .configMaps, .secrets, .persistentVolumes, .persistentVolumeClaims:
            return .config
        case .nodes, .serviceAccounts, .horizontalPodAutoscalers, .namespaces:
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
        }
    }

    var isNamespaced: Bool {
        switch self {
        case .nodes, .persistentVolumes, .ingressClasses, .namespaces:
            return false
        default:
            return true
        }
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
