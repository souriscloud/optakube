import Foundation

struct Pod: K8sResource {
    var apiVersion: String?
    var kind: String?
    var metadata: ObjectMeta
    var spec: PodSpec?
    var status: PodStatus?

    var phase: String { status?.phase ?? "Unknown" }
    var hostIP: String { status?.hostIP ?? "" }
    var podIP: String { status?.podIP ?? "" }
    var nodeName: String { spec?.nodeName ?? "" }

    var readyCount: Int {
        status?.containerStatuses?.filter { $0.ready }.count ?? 0
    }

    var totalContainers: Int {
        spec?.containers?.count ?? 0
    }

    var restartCount: Int {
        status?.containerStatuses?.reduce(0) { $0 + $1.restartCount } ?? 0
    }

    var resourceStatus: ResourceStatus {
        switch phase {
        case "Running":
            if readyCount == totalContainers && totalContainers > 0 {
                return .running
            }
            return .warning
        case "Succeeded": return .succeeded
        case "Pending": return .pending
        case "Failed": return .failed
        default: return .unknown
        }
    }
}

struct PodSpec: Codable, Sendable {
    var containers: [Container]?
    var initContainers: [Container]?
    var nodeName: String?
    var serviceAccountName: String?
    var restartPolicy: String?
    var volumes: [Volume]?
}

struct Container: Codable, Sendable, Identifiable {
    var name: String
    var image: String?
    var command: [String]?
    var args: [String]?
    var ports: [ContainerPort]?
    var env: [EnvVar]?
    var resources: ResourceRequirements?
    var volumeMounts: [VolumeMount]?
    var livenessProbe: Probe?
    var readinessProbe: Probe?
    var startupProbe: Probe?

    var id: String { name }
}

struct Probe: Codable, Sendable {
    var httpGet: HTTPGetAction?
    var tcpSocket: TCPSocketAction?
    var exec: ExecAction?
    var initialDelaySeconds: Int?
    var periodSeconds: Int?
    var timeoutSeconds: Int?
    var successThreshold: Int?
    var failureThreshold: Int?

    var methodDescription: String {
        if let http = httpGet {
            let scheme = http.scheme ?? "HTTP"
            let path = http.path ?? "/"
            let port = http.port?.displayValue ?? "?"
            return "\(scheme) GET \(path) on port \(port)"
        } else if let tcp = tcpSocket {
            return "TCP check on port \(tcp.port?.displayValue ?? "?")"
        } else if let exec = exec, let cmd = exec.command {
            return "Exec: \(cmd.joined(separator: " "))"
        }
        return "Unknown"
    }

    var methodType: String {
        if httpGet != nil { return "HTTP GET" }
        if tcpSocket != nil { return "TCP Socket" }
        if exec != nil { return "Exec" }
        return "Unknown"
    }

    var timingDescription: String {
        let initial = initialDelaySeconds ?? 0
        let period = periodSeconds ?? 10
        let timeout = timeoutSeconds ?? 1
        return "First probe \(initial)s after startup, then every \(period)s with \(timeout)s timeout"
    }

    var thresholdDescription: String {
        let success = successThreshold ?? 1
        let failure = failureThreshold ?? 3
        return "Status changes after \(success) success or \(failure) consecutive failures"
    }
}

struct HTTPGetAction: Codable, Sendable {
    var path: String?
    var port: IntOrString?
    var scheme: String?
}

struct TCPSocketAction: Codable, Sendable {
    var port: IntOrString?
}

struct ExecAction: Codable, Sendable {
    var command: [String]?
}


struct ContainerPort: Codable, Sendable {
    var name: String?
    var containerPort: Int
    var `protocol`: String?
}

struct EnvVar: Codable, Sendable {
    var name: String
    var value: String?
    var valueFrom: EnvVarSource?
}

struct EnvVarSource: Codable, Sendable {
    var configMapKeyRef: KeyRef?
    var secretKeyRef: KeyRef?
    var fieldRef: FieldRef?

    struct KeyRef: Codable, Sendable {
        var name: String
        var key: String
    }

    struct FieldRef: Codable, Sendable {
        var fieldPath: String
    }
}

struct ResourceRequirements: Codable, Sendable {
    var limits: [String: String]?
    var requests: [String: String]?
}

struct VolumeMount: Codable, Sendable {
    var name: String
    var mountPath: String
    var readOnly: Bool?
}

struct Volume: Codable, Sendable {
    var name: String
    var configMap: ConfigMapVolumeSource?
    var secret: SecretVolumeSource?
    var persistentVolumeClaim: PVCVolumeSource?
    var emptyDir: EmptyDirVolumeSource?
}

struct ConfigMapVolumeSource: Codable, Sendable {
    var name: String?
}

struct SecretVolumeSource: Codable, Sendable {
    var secretName: String?
}

struct PVCVolumeSource: Codable, Sendable {
    var claimName: String
}

struct EmptyDirVolumeSource: Codable, Sendable {
    var medium: String?
}

struct PodStatus: Codable, Sendable {
    var phase: String?
    var conditions: [PodCondition]?
    var containerStatuses: [ContainerStatus]?
    var initContainerStatuses: [ContainerStatus]?
    var hostIP: String?
    var podIP: String?
    var startTime: Date?
}

struct PodCondition: Codable, Sendable {
    var type: String
    var status: String
    var reason: String?
    var message: String?
    var lastTransitionTime: Date?
}

struct ContainerStatus: Codable, Sendable, Identifiable {
    var name: String
    var ready: Bool
    var restartCount: Int
    var image: String?
    var imageID: String?
    var state: ContainerState?
    var lastState: ContainerState?

    var id: String { name }
}

struct ContainerState: Codable, Sendable {
    var running: ContainerStateRunning?
    var waiting: ContainerStateWaiting?
    var terminated: ContainerStateTerminated?
}

struct ContainerStateRunning: Codable, Sendable {
    var startedAt: Date?
}

struct ContainerStateWaiting: Codable, Sendable {
    var reason: String?
    var message: String?
}

struct ContainerStateTerminated: Codable, Sendable {
    var exitCode: Int?
    var reason: String?
    var message: String?
    var startedAt: Date?
    var finishedAt: Date?
}
