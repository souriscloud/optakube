import Foundation

@Observable
final class PortForwardProcess: Identifiable, @unchecked Sendable {
    let id = UUID()
    let namespace: String
    let podName: String
    let localPort: Int
    let remotePort: Int
    let kubeconfigPath: String?
    let context: String?

    var isRunning: Bool = false
    var errorMessage: String?

    private var process: Process?

    init(namespace: String, podName: String, localPort: Int, remotePort: Int, kubeconfigPath: String?, context: String?) {
        self.namespace = namespace
        self.podName = podName
        self.localPort = localPort
        self.remotePort = remotePort
        self.kubeconfigPath = kubeconfigPath
        self.context = context
    }

    var displayName: String {
        "\(podName) \(localPort):\(remotePort)"
    }

    func start() {
        let proc = Process()
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        proc.executableURL = URL(fileURLWithPath: shell)

        var cmd = "kubectl port-forward"
        if let kc = kubeconfigPath {
            cmd += " --kubeconfig '\(kc)'"
        }
        if let ctx = context {
            cmd += " --context '\(ctx)'"
        }
        cmd += " -n \(namespace) \(podName) \(localPort):\(remotePort)"

        proc.arguments = ["-l", "-c", cmd]

        let stderrPipe = Pipe()
        proc.standardOutput = Pipe()
        proc.standardError = stderrPipe

        proc.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                self?.isRunning = false
                if proc.terminationStatus != 0 {
                    let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    self?.errorMessage = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }

        do {
            try proc.run()
            process = proc
            isRunning = true
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
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
