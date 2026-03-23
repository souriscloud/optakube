import Foundation

/// Represents a discovered Custom Resource Definition
struct CRDDefinition: Identifiable, Hashable, Codable {
    let group: String
    let version: String
    let kind: String
    let plural: String
    let singular: String
    let isNamespaced: Bool
    let displayName: String
    let category: String?

    var id: String { "\(group)/\(version)/\(plural)" }

    var apiPath: String {
        if group.isEmpty {
            return "/api/\(version)"
        }
        return "/apis/\(group)/\(version)"
    }

    func listURL(server: String, namespace: String?) -> URL? {
        var path: String
        if isNamespaced, let ns = namespace {
            path = "\(apiPath)/namespaces/\(ns)/\(plural)"
        } else {
            path = "\(apiPath)/\(plural)"
        }
        return URL(string: server + path)
    }
}

/// A generic K8s resource loaded from a CRD — stored as raw JSON
struct GenericK8sResource: Identifiable, Sendable {
    let raw: [String: Any]
    let crd: CRDDefinition

    var id: String {
        "\(namespace)/\(name)"
    }

    var name: String {
        (raw["metadata"] as? [String: Any])?["name"] as? String ?? "unknown"
    }

    var namespace: String {
        (raw["metadata"] as? [String: Any])?["namespace"] as? String ?? ""
    }

    var creationTimestamp: String {
        (raw["metadata"] as? [String: Any])?["creationTimestamp"] as? String ?? ""
    }

    var age: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallback = ISO8601DateFormatter()
        guard let date = formatter.date(from: creationTimestamp) ?? fallback.date(from: creationTimestamp) else { return "?" }
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "\(Int(interval))s" }
        if interval < 3600 { return "\(Int(interval / 60))m" }
        if interval < 86400 { return "\(Int(interval / 3600))h" }
        return "\(Int(interval / 86400))d"
    }

    var statusPhase: String {
        (raw["status"] as? [String: Any])?["phase"] as? String
            ?? (raw["status"] as? [String: Any])?["state"] as? String
            ?? ""
    }

    var jsonString: String {
        guard let data = try? JSONSerialization.data(withJSONObject: raw, options: [.prettyPrinted, .sortedKeys]),
              let str = String(data: data, encoding: .utf8) else { return "{}" }
        return str
    }
}

/// Sidebar selection can be a built-in ResourceType or a CRD
enum SidebarSelection: Hashable {
    case builtIn(ResourceType)
    case custom(CRDDefinition)

    var displayName: String {
        switch self {
        case .builtIn(let t): return t.displayName
        case .custom(let crd): return crd.displayName
        }
    }
}
