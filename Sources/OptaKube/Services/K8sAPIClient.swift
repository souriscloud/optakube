import Foundation
import Security

enum K8sError: Error, LocalizedError {
    case invalidURL
    case authFailed(String)
    case requestFailed(Int, String)
    case decodingFailed(String)
    case connectionFailed(String)
    case watchGone // 410 Gone — resourceVersion expired, need full re-list

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .authFailed(let msg): return "Auth failed: \(msg)"
        case .requestFailed(let code, let msg): return "HTTP \(code): \(msg)"
        case .decodingFailed(let msg): return "Decoding failed: \(msg)"
        case .connectionFailed(let msg): return "Connection failed: \(msg)"
        case .watchGone: return "Resource version expired"
        }
    }
}

// MARK: - Watch Types

enum WatchEventType: String, Codable {
    case ADDED, MODIFIED, DELETED, ERROR, BOOKMARK
}

struct WatchEvent<T: Codable>: Codable {
    let type: WatchEventType
    let object: T
}

struct ListResult<T> {
    let items: [T]
    let resourceVersion: String?
}

final class K8sAPIClient: NSObject, URLSessionDelegate, @unchecked Sendable {
    let connection: ClusterConnection
    let authProvider: any AuthProvider
    private var clientIdentity: SecIdentity?
    private var clientCertificate: SecCertificate?

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    // Watch session with no timeout (watches are long-lived)
    private lazy var watchSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 0
        config.timeoutIntervalForResource = 0
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    private static let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallbackFormatter = ISO8601DateFormatter()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let str = try container.decode(String.self)
            if let date = formatter.date(from: str) { return date }
            if let date = fallbackFormatter.date(from: str) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(str)")
        }
        return decoder
    }()

    init(connection: ClusterConnection) {
        self.connection = connection
        switch connection.authInfo {
        case .token(let token):
            self.authProvider = TokenAuthProvider(token: token)
        case .clientCertificate(let certData, let keyData):
            self.authProvider = ClientCertAuthProvider(certData: certData, keyData: keyData)
        case .exec(let command, let args, let env):
            self.authProvider = ExecAuthProvider(command: command, args: args, env: env)
        case .none:
            self.authProvider = NoAuthProvider()
        }
        super.init()

        // Pre-load client identity for TLS
        if case .clientCertificate(let certData, let keyData) = connection.authInfo {
            loadClientIdentity(certData: certData, keyData: keyData)
        }
    }

    // MARK: - Client Certificate Loading

    private func loadClientIdentity(certData: Data, keyData: Data) {
        // kubeconfig base64-decoded data is PEM-encoded.
        // Use openssl to create a PKCS12 bundle, then import it via SecPKCS12Import.
        // This handles RSA, EC, and any other key type that openssl supports.
        guard let certPEM = String(data: certData, encoding: .utf8),
              let keyPEM = String(data: keyData, encoding: .utf8) else { return }

        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let certFile = tmpDir.appendingPathComponent("cert.pem")
        let keyFile = tmpDir.appendingPathComponent("key.pem")
        let p12File = tmpDir.appendingPathComponent("bundle.p12")
        let password = "optakube-\(UUID().uuidString)"

        do {
            try certPEM.write(to: certFile, atomically: true, encoding: .utf8)
            try keyPEM.write(to: keyFile, atomically: true, encoding: .utf8)
        } catch { return }

        // Use openssl to create PKCS12
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
        process.arguments = [
            "pkcs12", "-export",
            "-out", p12File.path,
            "-inkey", keyFile.path,
            "-in", certFile.path,
            "-passout", "pass:\(password)"
        ]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch { return }

        guard process.terminationStatus == 0,
              let p12Data = try? Data(contentsOf: p12File) else { return }

        // Import PKCS12 into Security framework
        var items: CFArray?
        let options: [String: Any] = [kSecImportExportPassphrase as String: password]
        let status = SecPKCS12Import(p12Data as CFData, options as CFDictionary, &items)

        guard status == errSecSuccess,
              let itemArray = items as? [[String: Any]],
              let firstItem = itemArray.first,
              let identity = firstItem[kSecImportItemIdentity as String] else { return }

        self.clientIdentity = (identity as! SecIdentity)

        // Also extract the certificate for the TLS delegate
        var certRef: SecCertificate?
        SecIdentityCopyCertificate(self.clientIdentity!, &certRef)
        self.clientCertificate = certRef
    }

    private func pemToDER(_ data: Data, type: String) -> Data? {
        guard let pem = String(data: data, encoding: .utf8) else { return nil }
        let header = "-----BEGIN \(type)-----"
        let footer = "-----END \(type)-----"

        guard let headerRange = pem.range(of: header),
              let footerRange = pem.range(of: footer) else {
            return nil
        }

        let base64 = pem[headerRange.upperBound..<footerRange.lowerBound]
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .trimmingCharacters(in: .whitespaces)

        return Data(base64Encoded: base64)
    }

    // MARK: - CRD Discovery

    func discoverCRDs() async throws -> [CRDDefinition] {
        guard let url = URL(string: connection.server + "/apis/apiextensions.k8s.io/v1/customresourcedefinitions") else {
            throw K8sError.invalidURL
        }
        let data = try await request(url: url)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["items"] as? [[String: Any]] else {
            return []
        }

        return items.compactMap { item -> CRDDefinition? in
            guard let spec = item["spec"] as? [String: Any],
                  let group = spec["group"] as? String,
                  let names = spec["names"] as? [String: Any],
                  let kind = names["kind"] as? String,
                  let plural = names["plural"] as? String,
                  let scope = spec["scope"] as? String else { return nil }

            let singular = names["singular"] as? String ?? kind.lowercased()
            let categories = names["categories"] as? [String]

            // Get the preferred version
            var version = ""
            if let versions = spec["versions"] as? [[String: Any]] {
                // Prefer the served+storage version
                if let preferred = versions.first(where: { ($0["served"] as? Bool == true) && ($0["storage"] as? Bool == true) }) {
                    version = preferred["name"] as? String ?? ""
                } else if let first = versions.first {
                    version = first["name"] as? String ?? ""
                }
            }

            guard !version.isEmpty else { return nil }

            return CRDDefinition(
                group: group,
                version: version,
                kind: kind,
                plural: plural,
                singular: singular,
                isNamespaced: scope == "Namespaced",
                displayName: kind,
                category: categories?.first
            )
        }.sorted { $0.kind < $1.kind }
    }

    func listCustomResources(crd: CRDDefinition, namespace: String?) async throws -> [[String: Any]] {
        guard let url = crd.listURL(server: connection.server, namespace: crd.isNamespaced ? namespace : nil) else {
            throw K8sError.invalidURL
        }
        let data = try await request(url: url)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["items"] as? [[String: Any]] else {
            return []
        }
        return items
    }

    // MARK: - Events

    func listEvents(namespace: String?, fieldSelector: String? = nil) async throws -> [K8sEvent] {
        var urlString = connection.server + "/api/v1"
        if let ns = namespace {
            urlString += "/namespaces/\(ns)"
        }
        urlString += "/events"
        if let selector = fieldSelector {
            urlString += "?fieldSelector=\(selector.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? selector)"
        }
        guard let url = URL(string: urlString) else { throw K8sError.invalidURL }
        let data = try await request(url: url)
        let list = try Self.jsonDecoder.decode(K8sListResponse<K8sEvent>.self, from: data)
        return list.items
    }

    func listEventsForResource(kind: String, name: String, namespace: String?) async throws -> [K8sEvent] {
        let selector = "involvedObject.kind=\(kind),involvedObject.name=\(name)"
        return try await listEvents(namespace: namespace, fieldSelector: selector)
    }

    // MARK: - Resource Operations

    func list<T: K8sResource>(_ type: T.Type, resourceType: ResourceType, namespace: String? = nil) async throws -> [T] {
        let result = try await listWithVersion(type, resourceType: resourceType, namespace: namespace)
        return result.items
    }

    func listWithVersion<T: K8sResource>(_ type: T.Type, resourceType: ResourceType, namespace: String? = nil) async throws -> ListResult<T> {
        guard let url = resourceType.listURL(server: connection.server, namespace: namespace) else {
            throw K8sError.invalidURL
        }
        let data = try await request(url: url)
        let list = try Self.jsonDecoder.decode(K8sListResponse<T>.self, from: data)
        return ListResult(items: list.items, resourceVersion: list.metadata?.resourceVersion)
    }

    // MARK: - Watch API

    func watch<T: K8sResource>(_ type: T.Type, resourceType: ResourceType, namespace: String? = nil, resourceVersion: String) -> AsyncThrowingStream<WatchEvent<T>, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard var url = resourceType.listURL(server: connection.server, namespace: namespace) else {
                        continuation.finish(throwing: K8sError.invalidURL)
                        return
                    }
                    let separator = url.absoluteString.contains("?") ? "&" : "?"
                    guard let watchURL = URL(string: url.absoluteString + "\(separator)watch=true&resourceVersion=\(resourceVersion)&allowWatchBookmarks=true") else {
                        continuation.finish(throwing: K8sError.invalidURL)
                        return
                    }

                    var req = URLRequest(url: watchURL)
                    req.setValue("application/json", forHTTPHeaderField: "Accept")
                    if let token = try await authProvider.token() {
                        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    }

                    let (bytes, response) = try await watchSession.bytes(for: req)
                    guard let http = response as? HTTPURLResponse else {
                        continuation.finish(throwing: K8sError.connectionFailed("Invalid response"))
                        return
                    }
                    if http.statusCode == 410 {
                        continuation.finish(throwing: K8sError.watchGone)
                        return
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        continuation.finish(throwing: K8sError.requestFailed(http.statusCode, "Watch failed"))
                        return
                    }

                    for try await line in bytes.lines {
                        guard !line.isEmpty else { continue }
                        guard let lineData = line.data(using: .utf8) else { continue }
                        do {
                            let event = try Self.jsonDecoder.decode(WatchEvent<T>.self, from: lineData)
                            continuation.yield(event)
                        } catch {
                            // Skip unparseable lines (e.g. error objects)
                            continue
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func get<T: K8sResource>(_ type: T.Type, resourceType: ResourceType, name: String, namespace: String?) async throws -> T {
        guard var url = resourceType.listURL(server: connection.server, namespace: namespace) else {
            throw K8sError.invalidURL
        }
        url.appendPathComponent(name)
        let data = try await request(url: url)
        return try Self.jsonDecoder.decode(T.self, from: data)
    }

    func delete(resourceType: ResourceType, name: String, namespace: String?) async throws {
        guard var url = resourceType.listURL(server: connection.server, namespace: namespace) else {
            throw K8sError.invalidURL
        }
        url.appendPathComponent(name)
        _ = try await request(url: url, method: "DELETE")
    }

    func patch(resourceType: ResourceType, name: String, namespace: String?, body: Data) async throws {
        guard var url = resourceType.listURL(server: connection.server, namespace: namespace) else {
            throw K8sError.invalidURL
        }
        url.appendPathComponent(name)
        _ = try await request(url: url, method: "PATCH", body: body, contentType: "application/strategic-merge-patch+json")
    }

    func replace(resourceType: ResourceType, name: String, namespace: String?, body: Data) async throws {
        guard var url = resourceType.listURL(server: connection.server, namespace: namespace) else {
            throw K8sError.invalidURL
        }
        url.appendPathComponent(name)
        _ = try await request(url: url, method: "PUT", body: body, contentType: "application/json")
    }

    func scale(resourceType: ResourceType, name: String, namespace: String?, replicas: Int) async throws {
        guard var url = resourceType.listURL(server: connection.server, namespace: namespace) else {
            throw K8sError.invalidURL
        }
        url.appendPathComponent(name)
        url.appendPathComponent("scale")

        let scaleBody: [String: Any] = [
            "apiVersion": "autoscaling/v1",
            "kind": "Scale",
            "metadata": ["name": name, "namespace": namespace ?? "default"],
            "spec": ["replicas": replicas]
        ]
        let body = try JSONSerialization.data(withJSONObject: scaleBody)
        _ = try await request(url: url, method: "PUT", body: body, contentType: "application/json")
    }

    func restart(resourceType: ResourceType, name: String, namespace: String?) async throws {
        let now = ISO8601DateFormatter().string(from: Date())
        let patchBody: [String: Any] = [
            "spec": [
                "template": [
                    "metadata": [
                        "annotations": [
                            "kubectl.kubernetes.io/restartedAt": now
                        ]
                    ]
                ]
            ]
        ]
        let body = try JSONSerialization.data(withJSONObject: patchBody)
        try await patch(resourceType: resourceType, name: name, namespace: namespace, body: body)
    }

    // MARK: - CronJob Actions

    func triggerCronJob(name: String, namespace: String?) async throws {
        // Create a Job from the CronJob's jobTemplate
        guard let ns = namespace else { throw K8sError.invalidURL }
        guard let url = URL(string: "\(connection.server)/apis/batch/v1/namespaces/\(ns)/cronjobs/\(name)") else {
            throw K8sError.invalidURL
        }
        let cronJobData = try await request(url: url)
        guard let cronJob = try? JSONSerialization.jsonObject(with: cronJobData) as? [String: Any],
              let spec = cronJob["spec"] as? [String: Any],
              var jobTemplate = spec["jobTemplate"] as? [String: Any] else {
            throw K8sError.decodingFailed("Cannot parse CronJob template")
        }

        let jobName = "\(name)-manual-\(Int(Date().timeIntervalSince1970))"
        var jobMeta = (jobTemplate["metadata"] as? [String: Any]) ?? [:]
        jobMeta["name"] = jobName
        jobMeta["namespace"] = ns
        var annotations = (jobMeta["annotations"] as? [String: String]) ?? [:]
        annotations["cronjob.kubernetes.io/instantiate"] = "manual"
        jobMeta["annotations"] = annotations
        jobTemplate["metadata"] = jobMeta

        let jobBody: [String: Any] = [
            "apiVersion": "batch/v1",
            "kind": "Job",
            "metadata": jobMeta,
            "spec": jobTemplate["spec"] ?? [:]
        ]
        let body = try JSONSerialization.data(withJSONObject: jobBody)
        guard let createURL = URL(string: "\(connection.server)/apis/batch/v1/namespaces/\(ns)/jobs") else {
            throw K8sError.invalidURL
        }
        _ = try await request(url: createURL, method: "POST", body: body, contentType: "application/json")
    }

    func suspendCronJob(name: String, namespace: String?, suspend: Bool) async throws {
        let patchBody: [String: Any] = ["spec": ["suspend": suspend]]
        let body = try JSONSerialization.data(withJSONObject: patchBody)
        try await patch(resourceType: .cronJobs, name: name, namespace: namespace, body: body)
    }

    // MARK: - Deployment Rollback

    func listReplicaSetsForDeployment(name: String, namespace: String?) async throws -> [ReplicaSet] {
        let allRS = try await list(ReplicaSet.self, resourceType: .replicaSets, namespace: namespace)
        return allRS.filter { rs in
            rs.metadata.ownerReferences?.contains { $0.kind == "Deployment" && $0.name == name } == true
        }.sorted { rs1, rs2 in
            let rev1 = Int(rs1.metadata.annotations?["deployment.kubernetes.io/revision"] ?? "0") ?? 0
            let rev2 = Int(rs2.metadata.annotations?["deployment.kubernetes.io/revision"] ?? "0") ?? 0
            return rev1 > rev2
        }
    }

    func rollbackDeployment(name: String, namespace: String?, toRevision: Int) async throws {
        // Rollback by patching the deployment's template to match the target ReplicaSet's template
        let replicaSets = try await listReplicaSetsForDeployment(name: name, namespace: namespace)
        guard let targetRS = replicaSets.first(where: {
            Int($0.metadata.annotations?["deployment.kubernetes.io/revision"] ?? "") == toRevision
        }) else {
            throw K8sError.requestFailed(404, "Revision \(toRevision) not found")
        }

        // Get the full RS to extract its pod template
        let rs = try await get(ReplicaSet.self, resourceType: .replicaSets, name: targetRS.name, namespace: namespace)
        guard let template = rs.spec?.template else {
            throw K8sError.decodingFailed("ReplicaSet has no pod template")
        }

        // Get the RS as raw JSON to extract the full template
        guard var rsURL = ResourceType.replicaSets.listURL(server: connection.server, namespace: namespace) else {
            throw K8sError.invalidURL
        }
        rsURL.appendPathComponent(targetRS.name)
        let rsData = try await request(url: rsURL)
        guard let rsJSON = try? JSONSerialization.jsonObject(with: rsData) as? [String: Any],
              let rsSpec = rsJSON["spec"] as? [String: Any],
              let templateJSON = rsSpec["template"] else {
            throw K8sError.decodingFailed("Cannot parse ReplicaSet template")
        }

        let patchBody: [String: Any] = ["spec": ["template": templateJSON]]
        let body = try JSONSerialization.data(withJSONObject: patchBody)
        try await patch(resourceType: .deployments, name: name, namespace: namespace, body: body)
    }

    // MARK: - Debug Containers (Ephemeral)

    func addEphemeralContainer(podName: String, namespace: String?, containerName: String, image: String) async throws {
        guard let ns = namespace else { throw K8sError.invalidURL }
        guard let url = URL(string: "\(connection.server)/api/v1/namespaces/\(ns)/pods/\(podName)/ephemeralcontainers") else {
            throw K8sError.invalidURL
        }

        let ephemeralContainer: [String: Any] = [
            "name": containerName,
            "image": image,
            "stdin": true,
            "tty": true,
            "targetContainerName": ""
        ]

        // We need to PATCH the pod's ephemeralContainers using strategic merge patch
        let patchBody: [String: Any] = [
            "spec": [
                "ephemeralContainers": [ephemeralContainer]
            ]
        ]
        let body = try JSONSerialization.data(withJSONObject: patchBody)
        guard var podURL = ResourceType.pods.listURL(server: connection.server, namespace: namespace) else {
            throw K8sError.invalidURL
        }
        podURL.appendPathComponent(podName)
        podURL.appendPathComponent("ephemeralcontainers")
        _ = try await request(url: podURL, method: "PATCH", body: body, contentType: "application/strategic-merge-patch+json")
    }

    func getServerVersion() async throws -> String {
        guard let url = URL(string: connection.server + "/version") else {
            throw K8sError.invalidURL
        }
        let data = try await request(url: url)
        let version = try JSONDecoder().decode(ServerVersion.self, from: data)
        return "\(version.major).\(version.minor)"
    }

    func getRawYAML(resourceType: ResourceType, name: String, namespace: String?) async throws -> Data {
        guard var url = resourceType.listURL(server: connection.server, namespace: namespace) else {
            throw K8sError.invalidURL
        }
        url.appendPathComponent(name)
        return try await request(url: url)
    }

    // MARK: - Log Streaming

    /// Stream logs with server-side timestamps. Each line is prefixed with RFC3339 timestamp.
    func streamLogs(namespace: String, podName: String, container: String?, tailLines: Int = 1000, previous: Bool = false) -> AsyncThrowingStream<(Date, String), Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    var urlString = "\(connection.server)/api/v1/namespaces/\(namespace)/pods/\(podName)/log?follow=\(previous ? "false" : "true")&tailLines=\(tailLines)&timestamps=true"
                    if let c = container {
                        urlString += "&container=\(c)"
                    }
                    if previous {
                        urlString += "&previous=true"
                    }
                    guard let url = URL(string: urlString) else {
                        continuation.finish(throwing: K8sError.invalidURL)
                        return
                    }

                    var req = URLRequest(url: url)
                    if let token = try await authProvider.token() {
                        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    }

                    let (bytes, response) = try await session.bytes(for: req)
                    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                        continuation.finish(throwing: K8sError.requestFailed((response as? HTTPURLResponse)?.statusCode ?? 0, "Log stream failed"))
                        return
                    }

                    let tsFormatter = ISO8601DateFormatter()
                    tsFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    let tsFallback = ISO8601DateFormatter()

                    for try await line in bytes.lines {
                        // K8s timestamps=true format: "2024-01-15T10:30:45.123456789Z log message here"
                        let (ts, msg) = Self.parseTimestampedLine(line, formatter: tsFormatter, fallback: tsFallback)
                        continuation.yield((ts, msg))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Parse a timestamped log line from K8s (RFC3339Nano prefix separated by space)
    private static func parseTimestampedLine(_ line: String, formatter: ISO8601DateFormatter, fallback: ISO8601DateFormatter) -> (Date, String) {
        // Format: "2024-01-15T10:30:45.123456789Z actual log message"
        guard let spaceIdx = line.firstIndex(of: " ") else {
            return (Date(), line)
        }
        let tsStr = String(line[line.startIndex..<spaceIdx])
        let msg = String(line[line.index(after: spaceIdx)...])

        // K8s uses nanosecond precision — ISO8601DateFormatter handles up to microseconds
        // Truncate nanoseconds to fit: "2024-01-15T10:30:45.123456789Z" → "2024-01-15T10:30:45.123456Z"
        var cleanTs = tsStr
        if let dotIdx = cleanTs.firstIndex(of: "."), let zIdx = cleanTs.firstIndex(of: "Z") {
            let fracPart = cleanTs[cleanTs.index(after: dotIdx)..<zIdx]
            if fracPart.count > 6 {
                let truncated = String(fracPart.prefix(6))
                cleanTs = String(cleanTs[cleanTs.startIndex...dotIdx]) + truncated + "Z"
            }
        }

        if let date = formatter.date(from: cleanTs) { return (date, msg) }
        if let date = fallback.date(from: cleanTs) { return (date, msg) }
        return (Date(), line)
    }

    // MARK: - Namespaces

    func listNamespaces() async throws -> [String] {
        guard let url = URL(string: connection.server + "/api/v1/namespaces") else {
            throw K8sError.invalidURL
        }
        let data = try await request(url: url)
        struct NamespaceItem: Codable {
            var metadata: ObjectMeta
        }
        let list = try Self.jsonDecoder.decode(K8sListResponse<NamespaceItem>.self, from: data)
        return list.items.compactMap { $0.metadata.name }.sorted()
    }

    // MARK: - Metrics

    func listPodMetrics(namespace: String?) async throws -> [PodMetrics] {
        var urlString = connection.server + "/apis/metrics.k8s.io/v1beta1"
        if let ns = namespace {
            urlString += "/namespaces/\(ns)"
        }
        urlString += "/pods"
        guard let url = URL(string: urlString) else { throw K8sError.invalidURL }
        let data = try await request(url: url)
        let list = try Self.jsonDecoder.decode(K8sListResponse<PodMetrics>.self, from: data)
        return list.items
    }

    func listNodeMetrics() async throws -> [NodeMetrics] {
        guard let url = URL(string: connection.server + "/apis/metrics.k8s.io/v1beta1/nodes") else {
            throw K8sError.invalidURL
        }
        let data = try await request(url: url)
        let list = try Self.jsonDecoder.decode(K8sListResponse<NodeMetrics>.self, from: data)
        return list.items
    }

    // MARK: - HTTP

    private func request(url: URL, method: String = "GET", body: Data? = nil, contentType: String = "application/json") async throws -> Data {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.httpBody = body
        if body != nil {
            req.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        if let token = try await authProvider.token() {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw K8sError.connectionFailed("Invalid response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw K8sError.requestFailed(http.statusCode, body)
        }
        return data
    }

    // MARK: - URLSessionDelegate (TLS)

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        let protectionSpace = challenge.protectionSpace

        if protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            guard let serverTrust = protectionSpace.serverTrust else {
                return (.cancelAuthenticationChallenge, nil)
            }

            if connection.insecureSkipTLS {
                return (.useCredential, URLCredential(trust: serverTrust))
            }

            if let caData = connection.certificateAuthorityData {
                // The CA data from kubeconfig is already base64-decoded, but it's PEM inside
                let caDER = pemToDER(caData, type: "CERTIFICATE") ?? caData
                if let caCert = SecCertificateCreateWithData(nil, caDER as CFData) {
                    SecTrustSetAnchorCertificates(serverTrust, [caCert] as CFArray)
                    SecTrustSetAnchorCertificatesOnly(serverTrust, true)
                }
                return (.useCredential, URLCredential(trust: serverTrust))
            }

            return (.performDefaultHandling, nil)
        }

        if protectionSpace.authenticationMethod == NSURLAuthenticationMethodClientCertificate {
            if let identity = clientIdentity {
                let certs: [SecCertificate] = clientCertificate.map { [$0] } ?? []
                return (.useCredential, URLCredential(identity: identity, certificates: certs, persistence: .forSession))
            }
            return (.performDefaultHandling, nil)
        }

        return (.performDefaultHandling, nil)
    }
}

private struct ServerVersion: Codable {
    var major: String
    var minor: String
    var gitVersion: String?
}
