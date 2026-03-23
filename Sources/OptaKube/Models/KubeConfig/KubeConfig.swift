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

    struct ClusterEntry: Codable {
        var server: String
        var certificateAuthorityData: String?
        var certificateAuthority: String?
        var insecureSkipTLSVerify: Bool?

        enum CodingKeys: String, CodingKey {
            case server
            case certificateAuthorityData = "certificate-authority-data"
            case certificateAuthority = "certificate-authority"
            case insecureSkipTLSVerify = "insecure-skip-tls-verify"
        }
    }
}

struct NamedContext: Codable {
    var name: String
    var context: ContextEntry

    struct ContextEntry: Codable {
        var cluster: String
        var user: String
        var namespace: String?
    }
}

struct NamedUser: Codable {
    var name: String
    var user: UserEntry

    struct UserEntry: Codable {
        var token: String?
        var clientCertificateData: String?
        var clientKeyData: String?
        var clientCertificate: String?
        var clientKey: String?
        var exec: ExecConfig?

        enum CodingKeys: String, CodingKey {
            case token
            case clientCertificateData = "client-certificate-data"
            case clientKeyData = "client-key-data"
            case clientCertificate = "client-certificate"
            case clientKey = "client-key"
            case exec
        }
    }
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
