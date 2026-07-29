import XCTest
@testable import OptaKube

/// Covers the kubeconfig shapes that real clusters produce. The file-reference cases are
/// the default output of minikube, k3s and kubeadm, and were parsed into the model and
/// then never read — those clusters could not connect at all.
final class KubeConfigTests: XCTestCase {

    // MARK: - Auth resolution

    /// Stands in for the filesystem so these tests stay hermetic.
    private func reader(_ files: [String: String]) -> (String) -> Data? {
        { path in files[path]?.data(using: .utf8) }
    }

    private func user(_ yaml: String) throws -> NamedUser.UserEntry {
        let config = try KubeConfigService.decode(yaml: """
        users:
          - name: u
            user:
        \(yaml.split(separator: "\n").map { "      \($0)" }.joined(separator: "\n"))
        """)
        return try XCTUnwrap(config.users?.first?.user)
    }

    func testBearerTokenIsUsedDirectly() throws {
        let entry = try user("token: abc123")
        let auth = KubeConfigService.authInfo(for: entry, sourcePath: "/k/config", read: reader([:]))
        XCTAssertEqual(auth, .token("abc123"))
    }

    func testTokenFileIsRead() throws {
        let entry = try user("tokenFile: /var/run/token")
        let auth = KubeConfigService.authInfo(for: entry, sourcePath: "/k/config",
                                             read: reader(["/var/run/token": "file-token\n"]))
        // Trailing newline must be stripped or the Authorization header is malformed.
        XCTAssertEqual(auth, .token("file-token"))
    }

    func testEmbeddedClientCertificateData() throws {
        let cert = Data("cert".utf8).base64EncodedString()
        let key = Data("key".utf8).base64EncodedString()
        let entry = try user("""
        client-certificate-data: \(cert)
        client-key-data: \(key)
        """)
        let auth = KubeConfigService.authInfo(for: entry, sourcePath: "/k/config", read: reader([:]))
        XCTAssertEqual(auth, .clientCertificate(certData: Data("cert".utf8),
                                                keyData: Data("key".utf8)))
    }

    func testClientCertificateFilePathsAreRead() throws {
        // The minikube/k3s/kubeadm shape. This used to fall through to `.none`.
        let entry = try user("""
        client-certificate: /home/me/.minikube/client.crt
        client-key: /home/me/.minikube/client.key
        """)
        let auth = KubeConfigService.authInfo(
            for: entry, sourcePath: "/home/me/.kube/config",
            read: reader([
                "/home/me/.minikube/client.crt": "CERTPEM",
                "/home/me/.minikube/client.key": "KEYPEM",
            ]))
        XCTAssertEqual(auth, .clientCertificate(certData: Data("CERTPEM".utf8),
                                                keyData: Data("KEYPEM".utf8)))
    }

    func testUnreadableCertificateFilesAreReportedRatherThanSilentlyAnonymous() throws {
        let entry = try user("""
        client-certificate: /gone/client.crt
        client-key: /gone/client.key
        """)
        let auth = KubeConfigService.authInfo(for: entry, sourcePath: "/k/config", read: reader([:]))
        guard case .unsupported(let reason) = auth else {
            return XCTFail("expected .unsupported, got \(auth)")
        }
        XCTAssertTrue(reason.contains("/gone/client.crt"), reason)
    }

    func testExecCredentialPlugin() throws {
        let entry = try user("""
        exec:
          command: aws
          args:
            - eks
            - get-token
          env:
            - name: AWS_PROFILE
              value: prod
        """)
        let auth = KubeConfigService.authInfo(for: entry, sourcePath: "/k/config", read: reader([:]))
        XCTAssertEqual(auth, .exec(command: "aws", args: ["eks", "get-token"],
                                   env: ["AWS_PROFILE": "prod"]))
    }

    func testLegacyAuthProviderIsNamedNotSilentlyAnonymous() throws {
        let entry = try user("""
        auth-provider:
          name: oidc
        """)
        let auth = KubeConfigService.authInfo(for: entry, sourcePath: "/k/config", read: reader([:]))
        guard case .unsupported(let reason) = auth else {
            return XCTFail("expected .unsupported, got \(auth)")
        }
        XCTAssertTrue(reason.contains("oidc"), reason)
    }

    func testBasicAuthIsNamed() throws {
        let entry = try user("""
        username: admin
        password: hunter2
        """)
        let auth = KubeConfigService.authInfo(for: entry, sourcePath: "/k/config", read: reader([:]))
        guard case .unsupported(let reason) = auth else {
            return XCTFail("expected .unsupported, got \(auth)")
        }
        XCTAssertTrue(reason.lowercased().contains("basic"), reason)
    }

    func testMissingUserEntryIsNone() {
        XCTAssertEqual(
            KubeConfigService.authInfo(for: nil, sourcePath: "/k/config", read: reader([:])),
            .none)
    }

    // MARK: - Decode resilience

    func testOnePlaceholderClusterDoesNotDiscardTheWholeFile() throws {
        // YAMLDecoder is all-or-nothing. With non-optional fields, the `{}` entry below
        // failed the decode for the entire document and every context in it vanished from
        // the cluster list with no diagnostic anywhere.
        let config = try KubeConfigService.decode(yaml: """
        apiVersion: v1
        kind: Config
        current-context: good
        clusters:
          - name: placeholder
            cluster: {}
          - name: real
            cluster:
              server: https://10.0.0.1:6443
        contexts:
          - name: good
            context:
              cluster: real
              user: me
        users:
          - name: me
            user:
              token: t
        """)
        XCTAssertEqual(config.clusters?.count, 2)
        XCTAssertNil(config.clusters?.first(where: { $0.name == "placeholder" })?.cluster.server)
        XCTAssertEqual(config.clusters?.first(where: { $0.name == "real" })?.cluster.server,
                       "https://10.0.0.1:6443")
        XCTAssertEqual(config.currentContext, "good")
    }

    func testContextMissingAUserStillDecodes() throws {
        let config = try KubeConfigService.decode(yaml: """
        contexts:
          - name: partial
            context:
              cluster: only-cluster
        """)
        XCTAssertEqual(config.contexts?.count, 1)
        XCTAssertEqual(config.contexts?.first?.context.cluster, "only-cluster")
        XCTAssertNil(config.contexts?.first?.context.user)
    }

    func testCertificateAuthorityFilePathIsDecoded() throws {
        let config = try KubeConfigService.decode(yaml: """
        clusters:
          - name: mk
            cluster:
              server: https://127.0.0.1:6443
              certificate-authority: /home/me/.minikube/ca.crt
        """)
        XCTAssertEqual(config.clusters?.first?.cluster.certificateAuthority,
                       "/home/me/.minikube/ca.crt")
    }

    func testProxyURLAndTLSServerNameAreDecoded() throws {
        let config = try KubeConfigService.decode(yaml: """
        clusters:
          - name: corp
            cluster:
              server: https://api.internal:6443
              proxy-url: http://proxy.corp:3128
              tls-server-name: api.public
        """)
        let cluster = try XCTUnwrap(config.clusters?.first?.cluster)
        XCTAssertEqual(cluster.proxyURL, "http://proxy.corp:3128")
        XCTAssertEqual(cluster.tlsServerName, "api.public")
    }
}
