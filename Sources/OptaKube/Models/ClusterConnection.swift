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
    func portForward(namespace: String, podName: String, localPort: Int, remotePort: Int, kubeconfigPath: String?, context: String?) -> PortForwardProcess {
        PortForwardProcess(
            namespace: namespace,
            podName: podName,
            localPort: localPort,
            remotePort: remotePort,
            kubeconfigPath: kubeconfigPath,
            context: context
        )
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
