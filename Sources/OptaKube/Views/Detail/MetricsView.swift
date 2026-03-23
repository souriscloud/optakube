import SwiftUI
import Charts

// MARK: - Pod Metrics View

struct PodMetricsView: View {
    @Environment(AppViewModel.self) private var viewModel
    let podName: String
    let namespace: String?
    let clusterId: String

    @State private var metrics: PodMetrics?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var refreshTimer: Task<Void, Never>?

    var body: some View {
        Group {
            if isLoading && metrics == nil {
                ProgressView("Loading metrics...")
                    .frame(maxWidth: .infinity)
            } else if let error = errorMessage, metrics == nil {
                VStack(spacing: 8) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("Metrics not available")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding()
            } else if let metrics = metrics, let containers = metrics.containers, !containers.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    // CPU Chart
                    DetailSection("CPU Usage") {
                        Chart(containers) { container in
                            BarMark(
                                x: .value("CPU", container.cpuCores),
                                y: .value("Container", container.name)
                            )
                            .foregroundStyle(.blue.gradient)
                        }
                        .chartXAxisLabel("Cores")
                        .frame(height: CGFloat(containers.count * 36 + 30))
                    }

                    // Memory Chart
                    DetailSection("Memory Usage") {
                        Chart(containers) { container in
                            BarMark(
                                x: .value("Memory", container.memoryBytes / (1024 * 1024)),
                                y: .value("Container", container.name)
                            )
                            .foregroundStyle(.purple.gradient)
                        }
                        .chartXAxisLabel("MiB")
                        .frame(height: CGFloat(containers.count * 36 + 30))
                    }

                    // Detail table
                    DetailSection("Container Metrics") {
                        ForEach(containers) { container in
                            HStack {
                                Text(container.name)
                                    .fontWeight(.medium)
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("CPU: \(K8sQuantity.formatCPU(container.cpuCores))")
                                        .font(.system(.caption, design: .monospaced))
                                    Text("Mem: \(K8sQuantity.formatMemory(container.memoryBytes))")
                                        .font(.system(.caption, design: .monospaced))
                                }
                                .foregroundStyle(.secondary)
                            }
                            .padding(6)
                            .background(.quaternary.opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
            } else {
                Text("No container metrics available")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .onAppear {
            fetchMetrics()
            startAutoRefresh()
        }
        .onDisappear {
            refreshTimer?.cancel()
            refreshTimer = nil
        }
    }

    private func fetchMetrics() {
        guard let client = viewModel.activeClients[clusterId] else { return }
        Task {
            do {
                let allPodMetrics = try await client.listPodMetrics(namespace: namespace)
                let match = allPodMetrics.first { $0.name == podName }
                await MainActor.run {
                    metrics = match
                    isLoading = false
                    if match == nil { errorMessage = "No metrics found for this pod" }
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func startAutoRefresh() {
        refreshTimer?.cancel()
        refreshTimer = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled else { break }
                fetchMetrics()
            }
        }
    }
}

// MARK: - Node Metrics View

struct NodeMetricsView: View {
    let nodeMetrics: NodeMetrics
    let capacity: [String: String]?
    let allocatable: [String: String]?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // CPU gauge
            if let cpuCapStr = capacity?["cpu"] ?? allocatable?["cpu"] {
                let cpuCapacity = K8sQuantity.parseCPU(cpuCapStr)
                let cpuUsage = nodeMetrics.cpuCores
                let cpuPercent = cpuCapacity > 0 ? min(cpuUsage / cpuCapacity, 1.0) : 0

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("CPU")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                        Text("\(K8sQuantity.formatCPU(cpuUsage)) / \(K8sQuantity.formatCPU(cpuCapacity))")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Text("(\(Int(cpuPercent * 100))%)")
                            .font(.caption)
                            .foregroundStyle(utilizationColor(cpuPercent))
                    }
                    ProgressView(value: cpuPercent)
                        .tint(utilizationColor(cpuPercent))
                }
            }

            // Memory gauge
            if let memCapStr = capacity?["memory"] ?? allocatable?["memory"] {
                let memCapacity = K8sQuantity.parseMemory(memCapStr)
                let memUsage = nodeMetrics.memoryBytes
                let memPercent = memCapacity > 0 ? min(memUsage / memCapacity, 1.0) : 0

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Memory")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                        Text("\(K8sQuantity.formatMemory(memUsage)) / \(K8sQuantity.formatMemory(memCapacity))")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Text("(\(Int(memPercent * 100))%)")
                            .font(.caption)
                            .foregroundStyle(utilizationColor(memPercent))
                    }
                    ProgressView(value: memPercent)
                        .tint(utilizationColor(memPercent))
                }
            }
        }
    }

    private func utilizationColor(_ percent: Double) -> Color {
        if percent > 0.9 { return .red }
        if percent > 0.7 { return .orange }
        return .green
    }
}
