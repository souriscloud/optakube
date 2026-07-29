import Foundation

struct KubeConfig: Codable {
    var apiVersion: String?
    var kind: String?
    var currentContext: String?
    var clusters: [NamedCluster]?
    var contexts: [NamedContext]?
    var users: [NamedUser]?

    enum CodingKeys: String, CodingKey {
        case apiVersion
        case kind
        case currentContext = "current-context"
        case clusters
        case contexts
        case users
    }
}

struct NamedCluster: Codable {
    var name: String
    var cluster: ClusterEntry

    // Every field here is optional on purpose. YAMLDecoder is all-or-nothing, so one
    // placeholder entry (`cluster: {}`) or a templated stub used to fail the decode for
    // the entire file — and every context in it silently vanished from the cluster list.
    struct ClusterEntry: Codable {
        var server: String?
        var certificateAuthorityData: String?
        var certificateAuthority: String?
        var insecureSkipTLSVerify: Bool?
        var proxyURL: String?
        var tlsServerName: String?

        enum CodingKeys: String, CodingKey {
            case server
            case certificateAuthorityData = "certificate-authority-data"
            case certificateAuthority = "certificate-authority"
            case insecureSkipTLSVerify = "insecure-skip-tls-verify"
            case proxyURL = "proxy-url"
            case tlsServerName = "tls-server-name"
        }
    }
}

struct NamedContext: Codable {
    var name: String
    var context: ContextEntry

    struct ContextEntry: Codable {
        var cluster: String?
        var user: String?
        var namespace: String?
    }
}

struct NamedUser: Codable {
    var name: String
    var user: UserEntry

    struct UserEntry: Codable {
        var token: String?
        var tokenFile: String?
        var clientCertificateData: String?
        var clientKeyData: String?
        var clientCertificate: String?
        var clientKey: String?
        var exec: ExecConfig?
        var authProvider: AuthProviderConfig?
        var username: String?
        var password: String?

        enum CodingKeys: String, CodingKey {
            case token
            case tokenFile = "tokenFile"
            case clientCertificateData = "client-certificate-data"
            case clientKeyData = "client-key-data"
            case clientCertificate = "client-certificate"
            case clientKey = "client-key"
            case exec
            case authProvider = "auth-provider"
            case username
            case password
        }
    }
}

/// Legacy `auth-provider` block (gcp, oidc, azure). Not executed — decoded only so the
/// UI can name the unsupported mode rather than reporting a bare 401.
struct AuthProviderConfig: Codable {
    var name: String?
}

struct ExecConfig: Codable {
    var apiVersion: String?
    var command: String
    var args: [String]?
    var env: [ExecEnvVar]?
    var interactiveMode: String?
    var provideClusterInfo: Bool?

    enum CodingKeys: String, CodingKey {
        case apiVersion
        case command
        case args
        case env
        case interactiveMode
        case provideClusterInfo
    }
}

struct ExecEnvVar: Codable {
    var name: String
    var value: String
}

struct ExecCredential: Codable {
    var apiVersion: String?
    var kind: String?
    var status: ExecCredentialStatus?
}

struct ExecCredentialStatus: Codable {
    var token: String?
    var expirationTimestamp: String?
    var clientCertificateData: String?
    var clientKeyData: String?
}
