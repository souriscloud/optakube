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
        case .requestFailed(let code, let msg): return Self.describe(code: code, message: msg)
        case .decodingFailed(let msg): return "Decoding failed: \(msg)"
        case .connectionFailed(let msg): return "Connection failed: \(msg)"
        case .watchGone: return "Resource version expired"
        }
    }

    /// Turns an API-server status code into a sentence a user can act on. 401 and 403
    /// are the two failures people actually hit — expired SSO/exec credentials and
    /// missing RBAC — and they used to be indistinguishable truncated JSON blobs.
    private static func describe(code: Int, message: String) -> String {
        let detail = message.isEmpty ? "" : " \(message)"
        switch code {
        case 401:
            return "Credentials expired or invalid (401).\(detail) Re-authenticate (for example, re-run your cloud login) and retry."
        case 403:
            return "Not permitted (403).\(detail)"
        case 404:
            return "Not found (404).\(detail)"
        case 409:
            return "Conflict (409) — the resource changed on the server since it was read.\(detail)"
        case 410:
            return "Expired (410) — the data was too old to continue from; reloading.\(detail)"
        case 422:
            return "Rejected by the server (422).\(detail)"
        case 429:
            return "Rate limited by the API server (429).\(detail)"
        case 500...599:
            return "API server error (\(code)).\(detail)"
        default:
            return "HTTP \(code).\(detail)"
        }
    }

    /// Kubernetes reports failures as a `Status` object whose `message` is the
    /// human-readable part. Prefer it over dumping the raw JSON body at the user.
    static func humanMessage(from data: Data, statusCode: Int) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let message = json["message"] as? String, !message.isEmpty { return message }
            if let reason = json["reason"] as? String, !reason.isEmpty { return reason }
        }
        let raw = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if raw.isEmpty { return "" }
        return raw.count > 400 ? String(raw.prefix(400)) + "…" : raw
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

/// Tiny buffer that lets a watch consumer accumulate events while a debounce timer
/// runs concurrently. An actor (rather than a lock) because the producer loop and the
/// trailing-flush task both touch `pending` from different tasks. `add` reports whether
/// the buffer was empty so the caller knows to schedule a fresh flush window.
actor WatchCoalescer<T: K8sResource> {
    private var pending: [WatchEvent<T>] = []

    /// Append an event; returns true if the buffer was empty beforehand (i.e. the
    /// caller should start a new debounce window).
    func add(_ event: WatchEvent<T>) -> Bool {
        let wasEmpty = pending.isEmpty
        pending.append(event)
        return wasEmpty
    }

    func drain() -> [WatchEvent<T>] {
        let batch = pending
        pending.removeAll(keepingCapacity: true)
        return batch
    }
}

final class K8sAPIClient: Sendable {
    let connection: ClusterConnection
    let authProvider: any AuthProvider

    // All TLS trust + client-identity state lives in the delegate, which is the only
    // piece that needs `@unchecked Sendable` (URLSession invokes it off its own queue).
    // Keeping it out of K8sAPIClient lets the client itself be a clean `Sendable` type.
    private let trustDelegate: TLSTrustDelegate
    private let session: URLSession
    // Watch session with no timeout (watches are long-lived)
    private let watchSession: URLSession

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
        case .unsupported(let reason):
            // Fail with the reason instead of going out anonymous and returning a 401
            // that says nothing about the kubeconfig being the problem.
            self.authProvider = UnsupportedAuthProvider(reason: reason)
        }

        // Pre-load client identity for TLS (client-certificate auth only).
        var identity: SecIdentity?
        var certificate: SecCertificate?
        if case .clientCertificate(let certData, let keyData) = connection.authInfo {
            (identity, certificate) = Self.loadClientIdentity(certData: certData, keyData: keyData)
        }

        let delegate = TLSTrustDelegate(connection: connection, clientIdentity: identity, clientCertificate: certificate)
        self.trustDelegate = delegate

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)

        let watchConfig = URLSessionConfiguration.default
        // A watch is long-lived, so there's no overall resource deadline — but there *is*
        // a per-read one. With both set to 0 (no timeout at all), a socket left half-open
        // by a laptop sleep or a VPN reconnect produced no bytes and no error forever, and
        // nothing upstream could tell that the data on screen had stopped being true.
        // Slightly longer than the server-side `timeoutSeconds`, so a healthy watch is
        // always closed by the server first and this only fires when the socket is gone.
        watchConfig.timeoutIntervalForRequest = TimeInterval(Self.watchTimeoutSeconds + 60)
        watchConfig.timeoutIntervalForResource = 0
        self.watchSession = URLSession(configuration: watchConfig, delegate: delegate, delegateQueue: nil)
    }

    // MARK: - Client Certificate Loading

    private static func loadClientIdentity(certData: Data, keyData: Data) -> (SecIdentity?, SecCertificate?) {
        // kubeconfig base64-decoded data is PEM-encoded.
        // Use openssl to create a PKCS12 bundle, then import it via SecPKCS12Import.
        // This handles RSA, EC, and any other key type that openssl supports.
        guard let certPEM = String(data: certData, encoding: .utf8),
              let keyPEM = String(data: keyData, encoding: .utf8) else { return (nil, nil) }

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
        } catch { return (nil, nil) }

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
        } catch { return (nil, nil) }

        guard process.terminationStatus == 0,
              let p12Data = try? Data(contentsOf: p12File) else { return (nil, nil) }

        // Import PKCS12 into Security framework
        var items: CFArray?
        let options: [String: Any] = [kSecImportExportPassphrase as String: password]
        let status = SecPKCS12Import(p12Data as CFData, options as CFDictionary, &items)

        guard status == errSecSuccess,
              let itemArray = items as? [[String: Any]],
              let firstItem = itemArray.first,
              let identityItem = firstItem[kSecImportItemIdentity as String] else { return (nil, nil) }

        let identity = identityItem as! SecIdentity

        // Also extract the certificate for the TLS delegate
        var certRef: SecCertificate?
        SecIdentityCopyCertificate(identity, &certRef)
        return (identity, certRef)
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

    /// List Helm v3 releases by reading their backing `owner=helm` Secrets and decoding
    /// each. Returns every stored revision (the caller groups by release for history).
    func listHelmReleases(namespace: String?) async throws -> [HelmRelease] {
        var urlStr = connection.server + "/api/v1"
        if let ns = namespace { urlStr += "/namespaces/\(ns)" }
        urlStr += "/secrets?labelSelector=owner%3Dhelm"
        guard let url = URL(string: urlStr) else { throw K8sError.invalidURL }
        let data = try await request(url: url)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["items"] as? [[String: Any]] else { return [] }
        var releases: [HelmRelease] = []
        for item in items {
            let ns = (item["metadata"] as? [String: Any])?["namespace"] as? String ?? ""
            guard let rel = (item["data"] as? [String: Any])?["release"] as? String,
                  let decoded = HelmRelease.decode(fromSecretReleaseB64: rel, namespace: ns) else { continue }
            releases.append(decoded)
        }
        return releases
    }

    // MARK: - Helm uninstall / rollback support

    /// One backing Secret for a Helm release revision.
    struct HelmReleaseSecret: Sendable {
        let secretName: String
        let revision: Int
        let releaseB64: String   // value of data.release as returned by the API
        let status: String       // status label
    }

    /// DELETE an arbitrary resource by server-relative path.
    func deleteByPath(_ path: String) async throws {
        guard let url = URL(string: connection.server + path) else { throw K8sError.invalidURL }
        _ = try await request(url: url, method: "DELETE")
    }

    /// Evict a pod via the eviction subresource, so PodDisruptionBudgets are honoured.
    ///
    /// This goes through `request()` deliberately: earlier callers built their own
    /// `URLRequest` and sent it on `URLSession.shared`, which has none of this
    /// connection's TLS configuration — no kubeconfig CA anchor and no client
    /// `SecIdentity`. On every client-certificate cluster (kind, k3s, Rancher, most
    /// on-prem) that request went out anonymous and was rejected.
    func evict(podName: String, namespace: String) async throws {
        let eviction: [String: Any] = [
            "apiVersion": "policy/v1",
            "kind": "Eviction",
            "metadata": ["name": podName, "namespace": namespace],
        ]
        let body = try JSONSerialization.data(withJSONObject: eviction)
        guard let url = URL(string: connection.server
                            + "/api/v1/namespaces/\(namespace)/pods/\(podName)/eviction") else {
            throw K8sError.invalidURL
        }
        _ = try await request(url: url, method: "POST", body: body)
    }

    /// Fetch the backing Secrets for one Helm release (all revisions).
    func listHelmReleaseSecrets(release: String, namespace: String) async throws -> [HelmReleaseSecret] {
        let selector = "owner=helm,name=\(release)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "owner%3Dhelm"
        guard let url = URL(string: connection.server + "/api/v1/namespaces/\(namespace)/secrets?labelSelector=\(selector)") else {
            throw K8sError.invalidURL
        }
        let data = try await request(url: url)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["items"] as? [[String: Any]] else { return [] }
        return items.compactMap { item in
            let meta = item["metadata"] as? [String: Any]
            let labels = meta?["labels"] as? [String: Any]
            guard let secretName = meta?["name"] as? String,
                  let rel = (item["data"] as? [String: Any])?["release"] as? String else { return nil }
            let revision = Int((labels?["version"] as? String) ?? "") ?? 0
            return HelmReleaseSecret(secretName: secretName, revision: revision, releaseB64: rel,
                                     status: (labels?["status"] as? String) ?? "")
        }.sorted { $0.revision < $1.revision }
    }

    /// Create a Helm release-history Secret (POST). `dataReleaseB64` is the fully
    /// double-base64-encoded payload for `data.release`.
    func createHelmReleaseSecret(release: String, namespace: String, revision: Int,
                                 status: String, dataReleaseB64: String) async throws {
        let secretName = "sh.helm.release.v1.\(release).v\(revision)"
        let body: [String: Any] = [
            "apiVersion": "v1",
            "kind": "Secret",
            "type": "helm.sh/release.v1",
            "metadata": [
                "name": secretName,
                "namespace": namespace,
                "labels": ["name": release, "owner": "helm", "status": status, "version": "\(revision)"]
            ],
            "data": ["release": dataReleaseB64]
        ]
        let payload = try JSONSerialization.data(withJSONObject: body)
        guard let url = URL(string: connection.server + "/api/v1/namespaces/\(namespace)/secrets") else {
            throw K8sError.invalidURL
        }
        _ = try await request(url: url, method: "POST", body: payload, contentType: "application/json")
    }

    /// Patch a release Secret's status label + embedded payload (used to mark the prior
    /// current revision "superseded" on rollback).
    func patchHelmReleaseSecret(secretName: String, namespace: String, status: String, dataReleaseB64: String) async throws {
        let body: [String: Any] = [
            "metadata": ["labels": ["status": status]],
            "data": ["release": dataReleaseB64]
        ]
        let payload = try JSONSerialization.data(withJSONObject: body)
        guard let url = URL(string: connection.server + "/api/v1/namespaces/\(namespace)/secrets/\(secretName)") else {
            throw K8sError.invalidURL
        }
        _ = try await request(url: url, method: "PATCH", body: payload, contentType: "application/strategic-merge-patch+json")
    }

    /// Server-side apply a manifest (create-or-update) at a pre-resolved resource path
    /// like `/apis/apps/v1/namespaces/default/deployments/web`. Uses
    /// `application/apply-patch+yaml` with a stable field manager, so re-applying an
    /// edited manifest converges rather than erroring on conflict.
    func serverSideApply(path: String, yaml: String) async throws {
        guard let url = URL(string: connection.server + path + "?fieldManager=optakube&force=true") else {
            throw K8sError.invalidURL
        }
        let body = yaml.data(using: .utf8) ?? Data()
        _ = try await request(url: url, method: "PATCH", body: body, contentType: "application/apply-patch+yaml")
    }

    /// Fetch one custom resource's raw manifest (for the YAML editor).
    func getRawCustomResource(crd: CRDDefinition, name: String, namespace: String?) async throws -> Data {
        guard var url = crd.listURL(server: connection.server, namespace: crd.isNamespaced ? namespace : nil) else {
            throw K8sError.invalidURL
        }
        url.appendPathComponent(name)
        return try await request(url: url)
    }

    /// Replace (PUT) a custom resource with an edited manifest.
    func replaceCustomResource(crd: CRDDefinition, name: String, namespace: String?, body: Data) async throws {
        guard var url = crd.listURL(server: connection.server, namespace: crd.isNamespaced ? namespace : nil) else {
            throw K8sError.invalidURL
        }
        url.appendPathComponent(name)
        _ = try await request(url: url, method: "PUT", body: body, contentType: "application/json")
    }

    /// Delete a custom resource.
    func deleteCustomResource(crd: CRDDefinition, name: String, namespace: String?) async throws {
        guard var url = crd.listURL(server: connection.server, namespace: crd.isNamespaced ? namespace : nil) else {
            throw K8sError.invalidURL
        }
        url.appendPathComponent(name)
        _ = try await request(url: url, method: "DELETE")
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

    /// Field selector that scopes events to a single involved object.
    private static func eventFieldSelector(kind: String, name: String) -> String {
        "involvedObject.kind=\(kind),involvedObject.name=\(name)"
    }

    /// List a resource's events and return the list resourceVersion, so the caller can
    /// open a watch from exactly that point (no gap, no overlap).
    func listEventsForResourceWithVersion(kind: String, name: String, namespace: String?) async throws -> ListResult<K8sEvent> {
        var urlString = connection.server + "/api/v1"
        if let ns = namespace { urlString += "/namespaces/\(ns)" }
        urlString += "/events"
        let selector = Self.eventFieldSelector(kind: kind, name: name)
        if let encoded = selector.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            urlString += "?fieldSelector=\(encoded)"
        }
        guard let url = URL(string: urlString) else { throw K8sError.invalidURL }
        let data = try await request(url: url)
        let list = try Self.jsonDecoder.decode(K8sListResponse<K8sEvent>.self, from: data)
        return ListResult(items: list.items, resourceVersion: list.metadata?.resourceVersion)
    }

    /// Watch a single resource's events from `resourceVersion`. Mirrors the resource
    /// watch but on the events endpoint with an `involvedObject` field selector.
    func watchEventsForResource(kind: String, name: String, namespace: String?, resourceVersion: String) -> AsyncThrowingStream<WatchEvent<K8sEvent>, Error> {
        var urlString = connection.server + "/api/v1"
        if let ns = namespace { urlString += "/namespaces/\(ns)" }
        urlString += "/events"
        let selector = Self.eventFieldSelector(kind: kind, name: name)
        guard let encodedSelector = selector.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let watchURL = URL(string: urlString + "?fieldSelector=\(encodedSelector)&watch=true&resourceVersion=\(resourceVersion)&allowWatchBookmarks=true") else {
            return AsyncThrowingStream { $0.finish(throwing: K8sError.invalidURL) }
        }
        return streamWatch(watchURL: watchURL, as: K8sEvent.self)
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
        guard let url = resourceType.listURL(server: connection.server, namespace: namespace) else {
            return AsyncThrowingStream { $0.finish(throwing: K8sError.invalidURL) }
        }
        let separator = url.absoluteString.contains("?") ? "&" : "?"
        // `timeoutSeconds` makes the server close the watch on a schedule, exactly as
        // client-go does. Without it a connection wedged by a laptop sleep or a VPN
        // reconnect produces no bytes and no error indefinitely — the stream simply never
        // says anything again, and the data on screen silently stops being true.
        let params = "\(separator)watch=true&resourceVersion=\(resourceVersion)"
            + "&allowWatchBookmarks=true&timeoutSeconds=\(Self.watchTimeoutSeconds)"
        guard let watchURL = URL(string: url.absoluteString + params) else {
            return AsyncThrowingStream { $0.finish(throwing: K8sError.invalidURL) }
        }
        return streamWatch(watchURL: watchURL, as: T.self)
    }

    /// How long the server should hold a watch open before closing it cleanly. The loop
    /// reconnects, so this is invisible in the UI — it just bounds how long a dead socket
    /// can masquerade as a healthy one.
    static let watchTimeoutSeconds = 300

    /// Open a watch connection at `watchURL` and decode each streamed line as a
    /// `WatchEvent<T>`. Shared by `watch(_:resourceType:…)` and the events watch.
    /// On a 410 the stream finishes with `K8sError.watchGone` so callers can re-list.
    private func streamWatch<T: K8sResource>(watchURL: URL, as type: T.Type) -> AsyncThrowingStream<WatchEvent<T>, Error> {
        AsyncThrowingStream { continuation in
            let producer = Task {
                do {
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

                        // An expired resourceVersion is almost never an HTTP 410 in
                        // practice: the server answers 200 and then sends
                        // {"type":"ERROR","object":{"kind":"Status","code":410,…}} in the
                        // stream. That used to be discarded — either as an unparseable
                        // line or as an ignored ERROR event — and the stream then finished
                        // *cleanly*, so the caller reconnected immediately with the same
                        // dead resourceVersion, forever, without ever delivering an event.
                        if Self.isExpiredStatusLine(lineData) {
                            continuation.finish(throwing: K8sError.watchGone)
                            return
                        }

                        do {
                            let event = try Self.jsonDecoder.decode(WatchEvent<T>.self, from: lineData)
                            if event.type == .ERROR {
                                continuation.finish(throwing: K8sError.watchGone)
                                return
                            }
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
            // Without this the producer is orphaned: cancelling the consumer ends the
            // sequence but leaves this unstructured Task draining bytes.lines against a
            // session configured with no timeouts. Every sidebar click leaked one live
            // HTTP/2 stream that the API server would only close 30–60 minutes later.
            continuation.onTermination = { _ in producer.cancel() }
        }
    }

    /// True when a watch stream line is a `Status` reporting an expired resourceVersion.
    static func isExpiredStatusLine(_ line: Data) -> Bool {
        guard let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
            return false
        }
        // Either the bare Status, or a watch event wrapping one.
        let candidates: [[String: Any]] = [json, json["object"] as? [String: Any] ?? [:]]
        for candidate in candidates {
            guard candidate["kind"] as? String == "Status" else { continue }
            if let code = candidate["code"] as? Int, code == 410 { return true }
            if let reason = candidate["reason"] as? String, reason == "Expired" { return true }
        }
        return false
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

        // Sanity check: fetch the full RS to confirm it has a pod template before we
        // bother pulling the raw JSON to splice the template back into the deployment.
        let rs = try await get(ReplicaSet.self, resourceType: .replicaSets, name: targetRS.name, namespace: namespace)
        guard rs.spec?.template != nil else {
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
        // Validate the URL is constructable; the actual request below uses podURL built via ResourceType.
        guard URL(string: "\(connection.server)/api/v1/namespaces/\(ns)/pods/\(podName)/ephemeralcontainers") != nil else {
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

    // MARK: - Access Review (can-i)

    /// Result of a single `can-i` probe.
    struct AccessReviewResult: Sendable {
        let allowed: Bool
        let denied: Bool
        let reason: String?
    }

    /// Ask the API server whether the *current* kubeconfig identity may perform `verb`
    /// on a resource, via `SelfSubjectAccessReview` (authorization.k8s.io/v1). This is
    /// the `kubectl auth can-i` mechanism — it always works for the connected user and
    /// needs no extra RBAC, since everyone may review their own access.
    func selfSubjectAccessReview(verb: String, group: String, resource: String, namespace: String?) async throws -> AccessReviewResult {
        guard let url = URL(string: connection.server + "/apis/authorization.k8s.io/v1/selfsubjectaccessreviews") else {
            throw K8sError.invalidURL
        }
        var resourceAttributes: [String: Any] = [
            "verb": verb,
            "group": group,
            "resource": resource
        ]
        if let namespace { resourceAttributes["namespace"] = namespace }
        let payload: [String: Any] = [
            "apiVersion": "authorization.k8s.io/v1",
            "kind": "SelfSubjectAccessReview",
            "spec": ["resourceAttributes": resourceAttributes]
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let data = try await request(url: url, method: "POST", body: body, contentType: "application/json")

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = json["status"] as? [String: Any] else {
            return AccessReviewResult(allowed: false, denied: false, reason: "Unparseable response")
        }
        let allowed = status["allowed"] as? Bool ?? false
        let denied = status["denied"] as? Bool ?? false
        let reason = status["reason"] as? String
        return AccessReviewResult(allowed: allowed, denied: denied, reason: reason)
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
            let producer = Task {
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
            // As with streamWatch: closing the log view must actually stop the follow,
            // rather than leaving an unstructured task streaming a chatty pod's output.
            continuation.onTermination = { _ in producer.cancel() }
        }
    }

    /// Surfaces the reason a log stream failed. `streamLogs` reports a bare "Log stream
    /// failed", which hides the common cases — a 400 for "container X is not valid for
    /// pod", a 400 for "previous terminated container not found" behind the Previous
    /// toggle, or a 403 on pods/log.
    func logStreamFailureReason(namespace: String, podName: String, container: String?,
                                previous: Bool) async -> String? {
        var urlString = "\(connection.server)/api/v1/namespaces/\(namespace)/pods/\(podName)/log?tailLines=1"
        if let container { urlString += "&container=\(container)" }
        if previous { urlString += "&previous=true" }
        guard let url = URL(string: urlString) else { return nil }
        do {
            _ = try await request(url: url)
            return nil
        } catch {
            return error.localizedDescription
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

    private func request(url: URL, method: String = "GET", body: Data? = nil,
                         contentType: String = "application/json") async throws -> Data {
        do {
            return try await send(url: url, method: method, body: body, contentType: contentType)
        } catch K8sError.requestFailed(401, let message) {
            // A cached exec token can expire between the validity check and the request
            // landing. Re-acquire once and retry rather than surfacing a 401 the user can
            // only clear by restarting the app.
            await authProvider.invalidate()
            do {
                return try await send(url: url, method: method, body: body, contentType: contentType)
            } catch K8sError.requestFailed(401, let retryMessage) {
                throw K8sError.requestFailed(401, retryMessage.isEmpty ? message : retryMessage)
            }
        }
    }

    private func send(url: URL, method: String, body: Data?, contentType: String) async throws -> Data {
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

        // The delegate only clears this on a *successful* CA evaluation, so without an
        // explicit reset one early TLS rejection would keep re-labelling every later
        // timeout or connection-refused on this client as a certificate problem.
        trustDelegate.clearLastTLSError()

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw enrichTransportError(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw K8sError.connectionFailed("Invalid response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw K8sError.requestFailed(http.statusCode,
                                         K8sError.humanMessage(from: data, statusCode: http.statusCode))
        }
        return data
    }

    /// Replace URLSession's opaque TLS wrapper with the specific reason our delegate
    /// captured. When the delegate never fired (or fired and approved trust but URLSession
    /// rejected anyway, e.g. on ATS grounds), at least include the URLError code so the
    /// user sees something more diagnostic than the generic "A TLS error caused…".
    private func enrichTransportError(_ error: Error) -> Error {
        if let tls = trustDelegate.lastTLSError {
            return K8sError.connectionFailed("TLS: \(tls)")
        }
        if let urlError = error as? URLError {
            return K8sError.connectionFailed("\(urlError.localizedDescription) [URLError \(urlError.code.rawValue)]")
        }
        return error
    }

}

// MARK: - TLS Trust Delegate

/// URLSession delegate that owns all TLS trust + client-identity state for one
/// connection. Split out of `K8sAPIClient` so the client can be a clean `Sendable`
/// type: this is the only piece that genuinely needs `@unchecked Sendable`, because
/// URLSession invokes the challenge handler on its own delegate queue while
/// `lastTLSError` is read back from `request()`'s async context. The one cross-queue
/// mutable field is guarded by `lock`; identity/certificate are set once at init and
/// never mutated afterward.
final class TLSTrustDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    private let connection: ClusterConnection
    private let clientIdentity: SecIdentity?
    private let clientCertificate: SecCertificate?

    private let lock = NSLock()
    private var _lastTLSError: String?
    // Captured when server-trust evaluation rejects, so request() can surface the real
    // reason instead of the generic "A TLS error caused the secure connection to fail".
    var lastTLSError: String? {
        lock.lock(); defer { lock.unlock() }; return _lastTLSError
    }
    private func setLastTLSError(_ value: String?) {
        lock.lock(); _lastTLSError = value; lock.unlock()
    }
    /// Called at the start of every request so a stale reason can't mislabel a later,
    /// unrelated transport failure.
    func clearLastTLSError() {
        setLastTLSError(nil)
    }

    init(connection: ClusterConnection, clientIdentity: SecIdentity?, clientCertificate: SecCertificate?) {
        self.connection = connection
        self.clientIdentity = clientIdentity
        self.clientCertificate = clientCertificate
        super.init()
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

    // The completion-handler signature is the only one URLSession reliably finds via
    // `responds(to:)` in release builds. Swift's `async -> (...)` variant relies on
    // ObjC bridging that whole-module optimisation can strip — when that happens,
    // URLSession silently falls back to default handling, which rejects our custom CA
    // and surfaces the generic "A TLS error caused the secure connection to fail".
    // `@objc` here forces the symbol to be exported even under aggressive optimisation.
    @objc(URLSession:didReceiveChallenge:completionHandler:)
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        let protectionSpace = challenge.protectionSpace

        if protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            guard let serverTrust = protectionSpace.serverTrust else {
                setLastTLSError("no serverTrust in challenge")
                completionHandler(.cancelAuthenticationChallenge, nil)
                return
            }

            if connection.insecureSkipTLS {
                completionHandler(.useCredential, URLCredential(trust: serverTrust))
                return
            }

            if let caData = connection.certificateAuthorityData {
                // The CA data from kubeconfig is already base64-decoded, but it's PEM inside.
                // Parse out the DER bytes and use it as the only trust anchor (mirroring kubectl).
                guard let caDER = pemToDER(caData, type: "CERTIFICATE"),
                      let caCert = SecCertificateCreateWithData(nil, caDER as CFData) else {
                    setLastTLSError("failed to parse certificate-authority-data from kubeconfig")
                    completionHandler(.cancelAuthenticationChallenge, nil)
                    return
                }

                SecTrustSetAnchorCertificates(serverTrust, [caCert] as CFArray)
                SecTrustSetAnchorCertificatesOnly(serverTrust, true)

                // Evaluate explicitly so we can capture and surface the real reason on failure.
                var trustError: CFError?
                if SecTrustEvaluateWithError(serverTrust, &trustError) {
                    setLastTLSError(nil)
                    completionHandler(.useCredential, URLCredential(trust: serverTrust))
                    return
                }

                let reason = trustError.map { CFErrorCopyDescription($0) as String } ?? "unknown"
                let host = protectionSpace.host
                setLastTLSError("server trust for \(host): \(reason)")
                completionHandler(.cancelAuthenticationChallenge, nil)
                return
            }

            completionHandler(.performDefaultHandling, nil)
            return
        }

        if protectionSpace.authenticationMethod == NSURLAuthenticationMethodClientCertificate {
            if let identity = clientIdentity {
                let certs: [SecCertificate] = clientCertificate.map { [$0] } ?? []
                completionHandler(.useCredential, URLCredential(identity: identity, certificates: certs, persistence: .forSession))
                return
            }
            completionHandler(.performDefaultHandling, nil)
            return
        }

        completionHandler(.performDefaultHandling, nil)
    }
}

private struct ServerVersion: Codable {
    var major: String
    var minor: String
    var gitVersion: String?
}
