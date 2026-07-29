import Foundation

@Observable
final class PortForwardProcess: Identifiable, @unchecked Sendable {
    let id = UUID()
    let namespace: String
    /// The kubectl target, kind-qualified — `pod/web-0`, `service/web`. A bare name is
    /// resolved by kubectl as a pod, which is why Service forwards used to fail.
    let target: String
    let displayLabel: String
    let localPort: Int
    let remotePort: Int
    let kubeconfigPath: String?
    let context: String?

    var isRunning: Bool = false
    var errorMessage: String?

    private var process: Process?
    /// stderr is accumulated as it arrives. Draining it only after `waitUntilExit`, or
    /// on the main queue, is how this used to deadlock the UI: `readDataToEndOfFile`
    /// blocks until every writer closes the pipe, and a grandchild that inherited the
    /// descriptor keeps it open.
    private let stderrLock = NSLock()
    private var stderrBuffer = Data()

    init(namespace: String, target: String, displayLabel: String, localPort: Int,
         remotePort: Int, kubeconfigPath: String?, context: String?) {
        self.namespace = namespace
        self.target = target
        self.displayLabel = displayLabel
        self.localPort = localPort
        self.remotePort = remotePort
        self.kubeconfigPath = kubeconfigPath
        self.context = context
    }

    var displayName: String {
        "\(displayLabel) \(localPort):\(remotePort)"
    }

    func start() {
        let proc = Process()
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        proc.executableURL = URL(fileURLWithPath: shell)

        // `exec` so the login shell replaces itself with kubectl. Without it the PID we
        // hold is the shell's, and `terminate()` signals the shell while kubectl keeps
        // running and keeps the local port bound.
        var cmd = "exec kubectl port-forward"
        if let kc = kubeconfigPath {
            cmd += " --kubeconfig '\(kc)'"
        }
        if let ctx = context {
            cmd += " --context '\(ctx)'"
        }
        cmd += " -n '\(namespace)' '\(target)' \(localPort):\(remotePort)"

        proc.arguments = ["-l", "-c", cmd]

        // kubectl writes "Handling connection for <port>" to stdout for every single
        // connection. Nothing read that pipe, so after roughly 2,200 connections the
        // 64 KB kernel buffer filled and kubectl blocked in write(2) — the forward
        // stopped working while the UI still showed it as healthy.
        proc.standardOutput = FileHandle.nullDevice

        let stderrPipe = Pipe()
        proc.standardError = stderrPipe
        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            guard let self else { return }
            self.stderrLock.lock()
            self.stderrBuffer.append(chunk)
            self.stderrLock.unlock()
        }

        proc.terminationHandler = { [weak self] proc in
            guard let self else { return }
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            self.stderrLock.lock()
            let collected = self.stderrBuffer
            self.stderrLock.unlock()
            let message = String(data: collected, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            DispatchQueue.main.async {
                self.isRunning = false
                if proc.terminationStatus != 0, let message, !message.isEmpty {
                    self.errorMessage = message
                }
            }
        }

        do {
            try proc.run()
            process = proc
            isRunning = true
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't start kubectl: \(error.localizedDescription)"
            isRunning = false
        }
    }

    func stop() {
        process?.terminate()
        process = nil
        isRunning = false
    }
}

@Observable
final class PortForwardManager {
    static let shared = PortForwardManager()
    var activeForwards: [PortForwardProcess] = []

    private init() {}

    func add(_ pf: PortForwardProcess) {
        pf.start()
        activeForwards.append(pf)
    }

    func remove(_ pf: PortForwardProcess) {
        pf.stop()
        activeForwards.removeAll { $0.id == pf.id }
    }

    func stopAll() {
        activeForwards.forEach { $0.stop() }
        activeForwards.removeAll()
    }
}
