import Foundation
import Yams

actor KubeConfigService {
    enum Source: Codable, Hashable {
        case file(String)
        case directory(String)
    }

    /// One parsed kubeconfig plus the path it came from, so file-relative credential
    /// references can be resolved and connection IDs stay stable.
    private struct ParsedConfig {
        let path: String
        let config: KubeConfig
    }

    func loadConnections(from sources: [Source]) -> [ClusterConnection] {
        let parsed = parseAll(from: sources)
        return parsed.flatMap { extractConnections(from: $0, allConfigs: parsed) }
    }

    func loadDefaultConfig() -> [ClusterConnection] {
        let parsed = parseAll(from: Self.defaultSources())
        return parsed.flatMap { extractConnections(from: $0, allConfigs: parsed) }
    }

    /// kubectl reads `KUBECONFIG` as a colon-separated list before falling back to
    /// `~/.kube/config`. This was never consulted, so anyone using it — the standard way
    /// to keep per-cluster files separate — saw only the default path.
    static func defaultSources() -> [Source] {
        if let raw = ProcessInfo.processInfo.environment["KUBECONFIG"], !raw.isEmpty {
            let paths = raw.split(separator: ":").map(String.init)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            if !paths.isEmpty { return paths.map { .file($0) } }
        }
        return [.file("~/.kube/config")]
    }

    private func parseAll(from sources: [Source]) -> [ParsedConfig] {
        var result: [ParsedConfig] = []
        for source in sources {
            switch source {
            case .file(let path):
                let expanded = NSString(string: path).expandingTildeInPath
                if let config = parseKubeConfig(at: expanded) {
                    result.append(ParsedConfig(path: expanded, config: config))
                }
            case .directory(let path):
                let expanded = NSString(string: path).expandingTildeInPath
                guard let files = try? FileManager.default.contentsOfDirectory(atPath: expanded) else { continue }
                for file in files.sorted() {
                    let filePath = (expanded as NSString).appendingPathComponent(file)
                    if let config = parseKubeConfig(at: filePath) {
                        result.append(ParsedConfig(path: filePath, config: config))
                    }
                }
            }
        }
        return result
    }

    private func parseKubeConfig(at path: String) -> KubeConfig? {
        let expanded = NSString(string: path).expandingTildeInPath
        guard let data = FileManager.default.contents(atPath: expanded),
              let yaml = String(data: data, encoding: .utf8) else {
            return nil
        }
        return try? Self.decode(yaml: yaml)
    }

    /// Decodes a kubeconfig from YAML text. Internal so tests can exercise the model's
    /// tolerance of odd entries without touching the filesystem.
    static func decode(yaml: String) throws -> KubeConfig {
        try YAMLDecoder().decode(KubeConfig.self, from: yaml)
    }

    /// Reads a credential file referenced by a kubeconfig. Relative paths resolve against
    /// the kubeconfig's own directory, matching kubectl.
    private func readReferencedFile(_ ref: String, relativeTo configPath: String) -> Data? {
        let expanded = NSString(string: ref).expandingTildeInPath
        let url: URL
        if (expanded as NSString).isAbsolutePath {
            url = URL(fileURLWithPath: expanded)
        } else {
            let dir = (configPath as NSString).deletingLastPathComponent
            url = URL(fileURLWithPath: (dir as NSString).appendingPathComponent(expanded))
        }
        return try? Data(contentsOf: url)
    }

    private func extractConnections(from parsed: ParsedConfig,
                                    allConfigs: [ParsedConfig]) -> [ClusterConnection] {
        let config = parsed.config
        let sourcePath = parsed.path
        guard let contexts = config.contexts else { return [] }

        return contexts.compactMap { namedContext -> ClusterConnection? in
            let ctx = namedContext.context
            guard let clusterName = ctx.cluster else { return nil }

            // Look in this file first, then across every other loaded file. With
            // `KUBECONFIG=a:b` a context in one file routinely references a cluster or
            // user defined in another, and those contexts used to be dropped silently.
            let clusterEntry = config.clusters?.first { $0.name == clusterName }
                ?? allConfigs.compactMap { $0.config.clusters?.first { $0.name == clusterName } }.first
            let userEntry = ctx.user.flatMap { userName in
                config.users?.first { $0.name == userName }
                    ?? allConfigs.compactMap { $0.config.users?.first { $0.name == userName } }.first
            }

            guard let clusterEntry, let server = clusterEntry.cluster.server, !server.isEmpty else {
                return nil
            }

            let cluster = clusterEntry.cluster
            let user = userEntry?.user

            let authInfo = Self.authInfo(for: user, sourcePath: sourcePath,
                                         read: { self.readReferencedFile($0, relativeTo: sourcePath) })

            // Prefer the embedded CA, then the file reference. Only the embedded form was
            // ever read, so minikube/k3s/kubeadm configs — which write a path — had no CA
            // pinned at all and fell back to system trust, which rejects their self-signed
            // CA with an opaque TLS error.
            var caData: Data?
            if let caBase64 = cluster.certificateAuthorityData {
                caData = Data(base64Encoded: caBase64)
            } else if let caPath = cluster.certificateAuthority {
                caData = readReferencedFile(caPath, relativeTo: sourcePath)
            }

            return ClusterConnection(
                id: "\(sourcePath):\(namedContext.name)",
                name: namedContext.name,
                contextName: namedContext.name,
                server: server,
                defaultNamespace: ctx.namespace,
                authInfo: authInfo,
                certificateAuthorityData: caData,
                insecureSkipTLS: cluster.insecureSkipTLSVerify ?? false,
                isCurrentContext: config.currentContext == namedContext.name
            )
        }
    }

    /// Resolves a user entry to something the client can actually authenticate with.
    /// Unsupported modes are named rather than collapsed into `.none`, which used to
    /// surface as an unexplained 401 on a config that plainly carried credentials.
    static func authInfo(for user: NamedUser.UserEntry?,
                         sourcePath: String,
                         read: (String) -> Data?) -> ClusterConnection.AuthInfo {
        guard let user else { return .none }

        if let token = user.token, !token.isEmpty {
            return .token(token)
        }

        if let tokenFile = user.tokenFile,
           let data = read(tokenFile),
           let token = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !token.isEmpty {
            return .token(token)
        }

        // Embedded certificate data first, then file references.
        if let certData = user.clientCertificateData,
           let keyData = user.clientKeyData,
           let cert = Data(base64Encoded: certData),
           let key = Data(base64Encoded: keyData) {
            return .clientCertificate(certData: cert, keyData: key)
        }
        if let certPath = user.clientCertificate, let keyPath = user.clientKey {
            if let cert = read(certPath), let key = read(keyPath) {
                return .clientCertificate(certData: cert, keyData: key)
            }
            return .unsupported("client certificate files could not be read (\(certPath))")
        }

        if let exec = user.exec {
            var env: [String: String] = [:]
            exec.env?.forEach { env[$0.name] = $0.value }
            return .exec(command: exec.command, args: exec.args ?? [], env: env)
        }

        if let provider = user.authProvider?.name {
            return .unsupported("auth-provider \"\(provider)\" is not supported — "
                                + "convert it to an exec credential plugin")
        }
        if user.username != nil || user.password != nil {
            return .unsupported("basic authentication is not supported")
        }

        return .none
    }
}
