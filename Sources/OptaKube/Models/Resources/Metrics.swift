import Foundation

// MARK: - Metrics API Response Types

struct PodMetrics: Codable, Identifiable, Sendable {
    var metadata: ObjectMeta
    var timestamp: String?
    var window: String?
    var containers: [ContainerMetrics]?

    var id: String { "\(metadata.namespace ?? "")/\(metadata.name ?? "unknown")" }
    var name: String { metadata.name ?? "unknown" }
    var namespace: String { metadata.namespace ?? "default" }

    /// Total CPU usage across all containers in cores
    var totalCPU: Double {
        containers?.reduce(0) { $0 + K8sQuantity.parseCPU($1.usage.cpu) } ?? 0
    }

    /// Total memory usage across all containers in bytes
    var totalMemory: Double {
        containers?.reduce(0) { $0 + K8sQuantity.parseMemory($1.usage.memory) } ?? 0
    }
}

struct ContainerMetrics: Codable, Identifiable, Sendable {
    var name: String
    var usage: ResourceUsage

    var id: String { name }

    var cpuCores: Double { K8sQuantity.parseCPU(usage.cpu) }
    var memoryBytes: Double { K8sQuantity.parseMemory(usage.memory) }
}

struct ResourceUsage: Codable, Sendable {
    var cpu: String
    var memory: String
}

struct NodeMetrics: Codable, Identifiable, Sendable {
    var metadata: ObjectMeta
    var timestamp: String?
    var window: String?
    var usage: ResourceUsage

    var id: String { metadata.name ?? "unknown" }
    var name: String { metadata.name ?? "unknown" }

    var cpuCores: Double { K8sQuantity.parseCPU(usage.cpu) }
    var memoryBytes: Double { K8sQuantity.parseMemory(usage.memory) }
}

// MARK: - K8s Resource Quantity Parser

enum K8sQuantity {
    /// Parse CPU quantity string to cores (e.g. "100m" -> 0.1, "2" -> 2.0, "500n" -> 0.0000005)
    static func parseCPU(_ value: String) -> Double {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        if trimmed.hasSuffix("n") {
            let num = String(trimmed.dropLast())
            return (Double(num) ?? 0) / 1_000_000_000
        }
        if trimmed.hasSuffix("u") {
            let num = String(trimmed.dropLast())
            return (Double(num) ?? 0) / 1_000_000
        }
        if trimmed.hasSuffix("m") {
            let num = String(trimmed.dropLast())
            return (Double(num) ?? 0) / 1000
        }
        return Double(trimmed) ?? 0
    }

    /// Parse memory quantity string to bytes (e.g. "256Mi" -> 268435456, "1Gi" -> 1073741824)
    static func parseMemory(_ value: String) -> Double {
        let trimmed = value.trimmingCharacters(in: .whitespaces)

        // Binary suffixes (Ki, Mi, Gi, Ti, Pi, Ei)
        if trimmed.hasSuffix("Ki") {
            let num = String(trimmed.dropLast(2))
            return (Double(num) ?? 0) * 1024
        }
        if trimmed.hasSuffix("Mi") {
            let num = String(trimmed.dropLast(2))
            return (Double(num) ?? 0) * 1024 * 1024
        }
        if trimmed.hasSuffix("Gi") {
            let num = String(trimmed.dropLast(2))
            return (Double(num) ?? 0) * 1024 * 1024 * 1024
        }
        if trimmed.hasSuffix("Ti") {
            let num = String(trimmed.dropLast(2))
            return (Double(num) ?? 0) * 1024 * 1024 * 1024 * 1024
        }
        if trimmed.hasSuffix("Pi") {
            let num = String(trimmed.dropLast(2))
            return (Double(num) ?? 0) * 1024 * 1024 * 1024 * 1024 * 1024
        }
        if trimmed.hasSuffix("Ei") {
            let num = String(trimmed.dropLast(2))
            return (Double(num) ?? 0) * 1024 * 1024 * 1024 * 1024 * 1024 * 1024
        }

        // Decimal suffixes (k, M, G, T, P, E) - note lowercase k
        if trimmed.hasSuffix("E") && !trimmed.hasSuffix("Ei") {
            let num = String(trimmed.dropLast())
            return (Double(num) ?? 0) * 1e18
        }
        if trimmed.hasSuffix("P") && !trimmed.hasSuffix("Pi") {
            let num = String(trimmed.dropLast())
            return (Double(num) ?? 0) * 1e15
        }
        if trimmed.hasSuffix("T") && !trimmed.hasSuffix("Ti") {
            let num = String(trimmed.dropLast())
            return (Double(num) ?? 0) * 1e12
        }
        if trimmed.hasSuffix("G") && !trimmed.hasSuffix("Gi") {
            let num = String(trimmed.dropLast())
            return (Double(num) ?? 0) * 1e9
        }
        if trimmed.hasSuffix("M") && !trimmed.hasSuffix("Mi") {
            let num = String(trimmed.dropLast())
            return (Double(num) ?? 0) * 1e6
        }
        if trimmed.hasSuffix("k") {
            let num = String(trimmed.dropLast())
            return (Double(num) ?? 0) * 1e3
        }

        // Plain bytes
        return Double(trimmed) ?? 0
    }

    /// Format CPU cores to human-readable string (e.g. 0.1 -> "100m", 2.0 -> "2")
    static func formatCPU(_ cores: Double) -> String {
        if cores >= 1 {
            return cores.truncatingRemainder(dividingBy: 1) == 0
                ? "\(Int(cores))"
                : String(format: "%.1f", cores)
        }
        let millicores = Int(cores * 1000)
        return "\(millicores)m"
    }

    /// Format bytes to human-readable string (e.g. 268435456 -> "256Mi")
    static func formatMemory(_ bytes: Double) -> String {
        if bytes >= 1024 * 1024 * 1024 * 1024 {
            return String(format: "%.1fTi", bytes / (1024 * 1024 * 1024 * 1024))
        }
        if bytes >= 1024 * 1024 * 1024 {
            return String(format: "%.1fGi", bytes / (1024 * 1024 * 1024))
        }
        if bytes >= 1024 * 1024 {
            return String(format: "%.0fMi", bytes / (1024 * 1024))
        }
        if bytes >= 1024 {
            return String(format: "%.0fKi", bytes / 1024)
        }
        return "\(Int(bytes))B"
    }
}
