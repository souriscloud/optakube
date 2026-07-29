import Foundation

protocol AuthProvider: Sendable {
    func token() async throws -> String?
    func urlSessionDelegate() -> URLSessionDelegate?
    /// Drop any cached credential so the next `token()` acquires a fresh one. Called when
    /// the API server rejects a token that this provider still considered valid.
    func invalidate() async
}

extension AuthProvider {
    // Providers with nothing cached (static token, client cert, none) need do nothing.
    func invalidate() async {}
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

    /// Renew this far ahead of the stated expiry. An EKS token is valid for 15 minutes,
    /// and handing one out at T-1ms meant the request could easily land after `exp` once
    /// round-trip time and any apiserver/laptop clock skew were added — surfacing as a
    /// 401 the user had to restart the app to clear.
    private static let expiryMargin: TimeInterval = 60

    /// Used when the plugin returns no `expirationTimestamp`. Without this the cache was
    /// never considered valid, so *every* API request re-ran the credential plugin
    /// through a login shell — 0.3–2s each, serialised by this actor.
    private static let fallbackLifetime: TimeInterval = 300

    func token() async throws -> String? {
        if let cached = cachedToken, let expires = expiresAt,
           Date() < expires.addingTimeInterval(-Self.expiryMargin) {
            return cached
        }
        return try await refreshToken()
    }

    /// Discards the cached token so the next `token()` re-runs the plugin. Called when a
    /// request comes back 401 despite a cached token that looked valid.
    func invalidate() {
        cachedToken = nil
        expiresAt = nil
    }

    nonisolated func urlSessionDelegate() -> URLSessionDelegate? { nil }

    private func refreshToken() async throws -> String {
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
            // Single-quote every argument and escape any embedded single quotes. Quoting
            // only args containing spaces left `$`, `;`, backticks and quotes live in the
            // shell, which could break the command or inject into it.
            let fullCommand = ([command] + args)
                .map { "'" + $0.replacingOccurrences(of: "'", with: "'\\''") + "'" }
                .joined(separator: " ")
            process.arguments = ["-l", "-c", "exec \(fullCommand)"]
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

        // Both pipes are drained concurrently, before waiting for exit. Doing it the
        // other way round is the classic Process deadlock: a plugin that writes more than
        // the 64 KB pipe buffer before exiting blocks in write(2) forever, and since this
        // is awaited by every request(), one such hang wedged all traffic to the cluster
        // with the UI stuck on "Connecting…". A login shell makes it realistic — the
        // user's whole rc-file output lands in stdout first.
        let (outputData, stderrData) = await Self.drain(stdout: stdoutPipe, stderr: stderrPipe,
                                                        process: process)

        let stderrOutput = String(data: stderrData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard process.terminationStatus == 0 else {
            let detail = stderrOutput.isEmpty ? "exit code \(process.terminationStatus)" : stderrOutput
            throw K8sError.authFailed("\(command): \(detail)")
        }

        let credential: ExecCredential
        do {
            credential = try JSONDecoder().decode(ExecCredential.self, from: outputData)
        } catch {
            // A plugin that printed something other than an ExecCredential — a login-shell
            // banner, an interactive prompt, a Go panic — produced an opaque decode error.
            let hint = stderrOutput.isEmpty ? "" : "\n\(stderrOutput)"
            throw K8sError.authFailed("\(command) did not return a credential.\(hint)")
        }

        guard let token = credential.status?.token else {
            if credential.status?.clientCertificateData != nil {
                throw K8sError.authFailed(
                    "\(command) returned a client certificate rather than a token, "
                    + "which isn't supported yet.")
            }
            throw K8sError.authFailed("No token in \(command)'s credential response")
        }

        cachedToken = token
        expiresAt = Self.parseExpiry(credential.status?.expirationTimestamp)
            ?? Date().addingTimeInterval(Self.fallbackLifetime)

        return token
    }

    /// Reads both pipes to EOF concurrently, then reaps the process. A watchdog kills a
    /// plugin that never exits (an interactive OIDC device-code flow has no TTY here and
    /// would otherwise hang indefinitely).
    private static func drain(stdout: Pipe, stderr: Pipe,
                             process: Process) async -> (Data, Data) {
        let watchdog = Task {
            try? await Task.sleep(for: .seconds(60))
            if process.isRunning { process.terminate() }
        }
        defer { watchdog.cancel() }

        async let out = readToEnd(stdout.fileHandleForReading)
        async let err = readToEnd(stderr.fileHandleForReading)
        let collected = await (out, err)

        // Both descriptors are at EOF, so the child has closed them; this cannot block.
        process.waitUntilExit()
        return collected
    }

    private static func readToEnd(_ handle: FileHandle) async -> Data {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let data = (try? handle.readToEnd()) ?? Data()
                continuation.resume(returning: data)
            }
        }
    }

    /// `expirationTimestamp` is RFC3339, with or without fractional seconds. Anything
    /// unparseable falls back to a conservative lifetime rather than to "never valid".
    private static func parseExpiry(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFraction.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
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

/// Stands in for a kubeconfig auth mode this app can't perform. Failing loudly here is
/// better than sending an anonymous request and reporting the resulting 401, which tells
/// the user nothing about why their perfectly valid kubeconfig didn't work.
final class UnsupportedAuthProvider: AuthProvider, Sendable {
    private let reason: String

    init(reason: String) {
        self.reason = reason
    }

    func token() async throws -> String? {
        throw K8sError.authFailed(reason)
    }

    func urlSessionDelegate() -> URLSessionDelegate? { nil }
}
