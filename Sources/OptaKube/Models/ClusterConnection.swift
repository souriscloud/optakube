import Foundation

struct ClusterConnection: Identifiable, Hashable {
    let id: String
    let name: String
    let contextName: String
    let server: String
    let defaultNamespace: String?
    let authInfo: AuthInfo
    let certificateAuthorityData: Data?
    let insecureSkipTLS: Bool

    enum AuthInfo: Hashable {
        case token(String)
        case clientCertificate(certData: Data, keyData: Data)
        case exec(command: String, args: [String], env: [String: String])
        case none
    }
}

extension ClusterConnection {
    /// Builds a port-forward for a kind-qualified target. `resourceType` decides the
    /// kubectl prefix — a bare name is resolved as a pod, so Services need `service/`.
    func portForward(namespace: String, name: String, resourceType: ResourceType,
                     localPort: Int, remotePort: Int,
                     kubeconfigPath: String?, context: String?) -> PortForwardProcess {
        let kind: String
        switch resourceType {
        case .services: kind = "service"
        case .deployments: kind = "deployment"
        case .statefulSets: kind = "statefulset"
        default: kind = "pod"
        }
        return PortForwardProcess(
            namespace: namespace,
            target: "\(kind)/\(name)",
            displayLabel: name,
            localPort: localPort,
            remotePort: remotePort,
            kubeconfigPath: kubeconfigPath,
            context: context
        )
    }

    /// The kubeconfig file this connection was loaded from, parsed back out of `id`
    /// (which encodes as `"<path>:<contextName>"`). Centralises the split that several
    /// call sites used to do inline.
    var kubeconfigPath: String? {
        Self.splitID(id).path
    }

    /// Parse an arbitrary connection ID (e.g. from a `ResourceIdentifier.clusterId`)
    /// into its kubeconfig path and context-name components.
    static func splitID(_ id: String) -> (path: String?, contextName: String) {
        let parts = id.split(separator: ":", maxSplits: 1)
        let path = parts.first.map(String.init)
        let ctx = parts.count > 1 ? String(parts[1]) : ""
        return (path, ctx)
    }
}

enum ConnectionStatus: Equatable {
    case disconnected
    case connecting
    case connected(serverVersion: String)
    case error(String)

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}
