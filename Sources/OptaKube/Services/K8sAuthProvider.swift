import Foundation

protocol AuthProvider: Sendable {
    func token() async throws -> String?
    func urlSessionDelegate() -> URLSessionDelegate?
}

final class TokenAuthProvider: AuthProvider, Sendable {
    private let bearerToken: String

    init(token: String) {
        self.bearerToken = token
    }

    func token() async throws -> String? { bearerToken }
    func urlSessionDelegate() -> URLSessionDelegate? { nil }
}

actor ExecAuthProvider: AuthProvider {
    private let command: String
    private let args: [String]
    private let env: [String: String]
    private var cachedToken: String?
    private var expiresAt: Date?

    init(command: String, args: [String], env: [String: String]) {
        self.command = command
        self.args = args
        self.env = env
    }

    func token() async throws -> String? {
        if let cached = cachedToken, let expires = expiresAt, Date() < expires {
            return cached
        }
        return try refreshToken()
    }

    nonisolated func urlSessionDelegate() -> URLSessionDelegate? { nil }

    private func refreshToken() throws -> String {
        let process = Process()

        // Resolve command path — use login shell to get full PATH
        if command.hasPrefix("/") {
            process.executableURL = URL(fileURLWithPath: command)
            process.arguments = args
        } else {
            // Use the user's shell to resolve the command (inherits PATH from shell profile)
            let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
            process.executableURL = URL(fileURLWithPath: shell)
            // Use -l for login shell (loads .zshrc/.bash_profile), -c to run command
            let fullCommand = ([command] + args).map { arg in
                // Quote args that contain spaces
                arg.contains(" ") ? "'\(arg)'" : arg
            }.joined(separator: " ")
            process.arguments = ["-l", "-c", fullCommand]
        }

        var environment = ProcessInfo.processInfo.environment
        for (key, value) in env {
            environment[key] = value
        }
        process.environment = environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrOutput = String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard process.terminationStatus == 0 else {
            let detail = stderrOutput.isEmpty ? "exit code \(process.terminationStatus)" : stderrOutput
            throw K8sError.authFailed("\(command): \(detail)")
        }

        let outputData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let credential = try JSONDecoder().decode(ExecCredential.self, from: outputData)

        guard let token = credential.status?.token else {
            throw K8sError.authFailed("No token in exec credential response")
        }

        cachedToken = token
        if let expiresStr = credential.status?.expirationTimestamp {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            expiresAt = formatter.date(from: expiresStr)
                ?? ISO8601DateFormatter().date(from: expiresStr)
        }

        return token
    }
}

final class ClientCertAuthProvider: AuthProvider, @unchecked Sendable {
    let certData: Data
    let keyData: Data

    init(certData: Data, keyData: Data) {
        self.certData = certData
        self.keyData = keyData
    }

    func token() async throws -> String? { nil }
    func urlSessionDelegate() -> URLSessionDelegate? { nil }
}

final class NoAuthProvider: AuthProvider, Sendable {
    func token() async throws -> String? { nil }
    func urlSessionDelegate() -> URLSessionDelegate? { nil }
}
