import Foundation
import Yams

actor KubeConfigService {
    enum Source: Codable, Hashable {
        case file(String)
        case directory(String)
    }

    func loadConnections(from sources: [Source]) -> [ClusterConnection] {
        var connections: [ClusterConnection] = []
        for source in sources {
            switch source {
            case .file(let path):
                if let config = parseKubeConfig(at: path) {
                    connections.append(contentsOf: extractConnections(from: config, sourcePath: path))
                }
            case .directory(let path):
                let expanded = NSString(string: path).expandingTildeInPath
                guard let files = try? FileManager.default.contentsOfDirectory(atPath: expanded) else { continue }
                for file in files {
                    let filePath = (expanded as NSString).appendingPathComponent(file)
                    if let config = parseKubeConfig(at: filePath) {
                        connections.append(contentsOf: extractConnections(from: config, sourcePath: filePath))
                    }
                }
            }
        }
        return connections
    }

    func loadDefaultConfig() -> [ClusterConnection] {
        let defaultPath = NSString(string: "~/.kube/config").expandingTildeInPath
        guard let config = parseKubeConfig(at: defaultPath) else { return [] }
        return extractConnections(from: config, sourcePath: defaultPath)
    }

    private func parseKubeConfig(at path: String) -> KubeConfig? {
        let expanded = NSString(string: path).expandingTildeInPath
        guard let data = FileManager.default.contents(atPath: expanded),
              let yaml = String(data: data, encoding: .utf8) else {
            return nil
        }
        do {
            let decoder = YAMLDecoder()
            return try decoder.decode(KubeConfig.self, from: yaml)
        } catch {
            return nil
        }
    }

    private func extractConnections(from config: KubeConfig, sourcePath: String) -> [ClusterConnection] {
        guard let contexts = config.contexts else { return [] }

        return contexts.compactMap { namedContext in
            let ctx = namedContext.context

            guard let clusterEntry = config.clusters?.first(where: { $0.name == ctx.cluster }),
                  let userEntry = config.users?.first(where: { $0.name == ctx.user }) else {
                return nil
            }

            let cluster = clusterEntry.cluster
            let user = userEntry.user

            let authInfo: ClusterConnection.AuthInfo
            if let token = user.token {
                authInfo = .token(token)
            } else if let certData = user.clientCertificateData,
                      let keyData = user.clientKeyData,
                      let cert = Data(base64Encoded: certData),
                      let key = Data(base64Encoded: keyData) {
                authInfo = .clientCertificate(certData: cert, keyData: key)
            } else if let exec = user.exec {
                var env: [String: String] = [:]
                exec.env?.forEach { env[$0.name] = $0.value }
                authInfo = .exec(command: exec.command, args: exec.args ?? [], env: env)
            } else {
                authInfo = .none
            }

            var caData: Data? = nil
            if let caBase64 = cluster.certificateAuthorityData {
                caData = Data(base64Encoded: caBase64)
            }

            return ClusterConnection(
                id: "\(sourcePath):\(namedContext.name)",
                name: namedContext.name,
                contextName: namedContext.name,
                server: cluster.server,
                defaultNamespace: ctx.namespace,
                authInfo: authInfo,
                certificateAuthorityData: caData,
                insecureSkipTLS: cluster.insecureSkipTLSVerify ?? false
            )
        }
    }
}
