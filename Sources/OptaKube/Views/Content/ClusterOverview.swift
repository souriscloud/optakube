import SwiftUI
import Charts

struct ClusterOverview: View {
    @Environment(AppViewModel.self) private var viewModel
    @State private var clusterEvents: [K8sEvent] = []
    @State private var isLoadingEvents = false
    @State private var refreshTimer: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Cluster info cards
                ForEach(Array(viewModel.selectedClusterIds), id: \.self) { clusterId in
                    if let conn = viewModel.availableConnections.first(where: { $0.id == clusterId }) {
                        clusterCard(connection: conn, clusterId: clusterId)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Cluster Overview")
        .onAppear {
            loadOverviewData()
            startAutoRefresh()
        }
        .onDisappear {
            refreshTimer?.cancel()
            refreshTimer = nil
        }
    }

    // MARK: - Cluster Card

    @ViewBuilder
    private func clusterCard(connection: ClusterConnection, clusterId: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: "server.rack")
                    .font(.title2)
                    .foregroundStyle(.blue)
                VStack(alignment: .leading) {
                    Text(connection.name)
                        .font(.title2)
                        .fontWeight(.semibold)
                    if case .connected(let version) = viewModel.connectionStatuses[clusterId] {
                        Text("Kubernetes v\(version)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                statusBadge(for: clusterId)
            }

            Divider()

            // Resource summary
            resourceSummary(for: clusterId)

            Divider()

            // Node status with metrics
            nodeSection(for: clusterId)

            Divider()

            // Cluster resource utilization
            clusterUtilization(for: clusterId)

            Divider()

            // Recent events
            eventsSection(for: clusterId)
        }
        .padding()
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
    }

    // MARK: - Status Badge

    @ViewBuilder
    private func statusBadge(for clusterId: String) -> some View {
        let status = viewModel.connectionStatuses[clusterId] ?? .disconnected
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor(status))
                .frame(width: 8, height: 8)
            Text(statusText(status))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.quaternary.opacity(0.5))
        .clipShape(Capsule())
    }

    // MARK: - Resource Summary

    @ViewBuilder
    private func resourceSummary(for clusterId: String) -> some View {
        let allPods = viewModel.pods[clusterId] ?? []
        let allDeployments = viewModel.deployments[clusterId] ?? []
        let allServices = viewModel.services[clusterId] ?? []
        let allNodes = viewModel.nodes[clusterId] ?? []
        let nsCount = viewModel.availableNamespaces[clusterId]?.count ?? 0

        VStack(alignment: .leading, spacing: 8) {
            Text("Resource Summary")
                .font(.headline)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                summaryCard(title: "Nodes", value: "\(allNodes.count)", icon: "desktopcomputer", color: .blue)
                summaryCard(title: "Namespaces", value: "\(nsCount)", icon: "folder", color: .indigo)
                summaryCard(title: "Pods", value: "\(allPods.count)", icon: "cube", color: .green)
                summaryCard(title: "Deployments", value: "\(allDeployments.count)", icon: "arrow.triangle.2.circlepath", color: .orange)
                summaryCard(title: "Services", value: "\(allServices.count)", icon: "network", color: .purple)
            }

            // Pod status breakdown
            if !allPods.isEmpty {
                let running = allPods.filter { $0.resourceStatus == .running }.count
                let pending = allPods.filter { $0.resourceStatus == .pending }.count
                let failed = allPods.filter { $0.resourceStatus == .failed }.count
                let other = allPods.count - running - pending - failed

                HStack(spacing: 16) {
                    podStatusLabel("Running", count: running, color: .green)
                    podStatusLabel("Pending", count: pending, color: .orange)
                    podStatusLabel("Failed", count: failed, color: .red)
                    if other > 0 {
                        podStatusLabel("Other", count: other, color: .gray)
                    }
                }
                .font(.caption)
                .padding(.top, 4)
            }
        }
    }

    @ViewBuilder
    private func summaryCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .monospacedDigit()
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func podStatusLabel(_ label: String, count: Int, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text("\(count) \(label)")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Node Section

    @ViewBuilder
    private func nodeSection(for clusterId: String) -> some View {
        let allNodes = viewModel.nodes[clusterId] ?? []
        let nodeMetrics = viewModel.nodeMetricsCache[clusterId] ?? []
        let metricsAvail = viewModel.metricsAvailable[clusterId] ?? false

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Nodes")
                    .font(.headline)
                Spacer()
                if !metricsAvail && !nodeMetrics.isEmpty == false {
                    Text("Metrics server not available")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(allNodes, id: \.id) { node in
                let readyCondition = node.status?.conditions?.first { $0.type == "Ready" }
                let isReady = readyCondition?.status == "True"
                let matching = nodeMetrics.first { $0.name == node.name }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: isReady ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(isReady ? .green : .red)
                            .font(.caption)
                        Text(node.name)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        Spacer()
                        Text(node.roles.isEmpty ? "worker" : node.roles)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(node.kubeletVersion)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    if let nm = matching {
                        NodeMetricsView(
                            nodeMetrics: nm,
                            capacity: node.status?.capacity,
                            allocatable: node.status?.allocatable
                        )
                    }
                }
                .padding(8)
                .background(.quaternary.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    // MARK: - Cluster Utilization

    @ViewBuilder
    private func clusterUtilization(for clusterId: String) -> some View {
        let nodeMetrics = viewModel.nodeMetricsCache[clusterId] ?? []
        let allNodes = viewModel.nodes[clusterId] ?? []

        if !nodeMetrics.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Cluster Utilization")
                    .font(.headline)

                let totalCPUUsage = nodeMetrics.reduce(0) { $0 + $1.cpuCores }
                let totalMemUsage = nodeMetrics.reduce(0) { $0 + $1.memoryBytes }
                let totalCPUCapacity = allNodes.reduce(0.0) { $0 + K8sQuantity.parseCPU($1.status?.capacity?["cpu"] ?? "0") }
                let totalMemCapacity = allNodes.reduce(0.0) { $0 + K8sQuantity.parseMemory($1.status?.capacity?["memory"] ?? "0") }

                HStack(spacing: 24) {
                    // CPU utilization chart
                    VStack(spacing: 4) {
                        Text("CPU")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        if totalCPUCapacity > 0 {
                            let cpuPercent = totalCPUUsage / totalCPUCapacity
                            Gauge(value: min(cpuPercent, 1.0)) {
                                EmptyView()
                            } currentValueLabel: {
                                Text("\(Int(cpuPercent * 100))%")
                                    .font(.system(.title3, design: .monospaced))
                                    .fontWeight(.bold)
                            }
                            .gaugeStyle(.accessoryCircular)
                            .tint(utilizationGradient(cpuPercent))
                            .scaleEffect(1.5)
                            .frame(width: 80, height: 80)

                            Text("\(K8sQuantity.formatCPU(totalCPUUsage)) / \(K8sQuantity.formatCPU(totalCPUCapacity))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.top, 8)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    // Memory utilization chart
                    VStack(spacing: 4) {
                        Text("Memory")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        if totalMemCapacity > 0 {
                            let memPercent = totalMemUsage / totalMemCapacity
                            Gauge(value: min(memPercent, 1.0)) {
                                EmptyView()
                            } currentValueLabel: {
                                Text("\(Int(memPercent * 100))%")
                                    .font(.system(.title3, design: .monospaced))
                                    .fontWeight(.bold)
                            }
                            .gaugeStyle(.accessoryCircular)
                            .tint(utilizationGradient(memPercent))
                            .scaleEffect(1.5)
                            .frame(width: 80, height: 80)

                            Text("\(K8sQuantity.formatMemory(totalMemUsage)) / \(K8sQuantity.formatMemory(totalMemCapacity))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.top, 8)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.vertical, 8)

                // Per-node bar chart
                if nodeMetrics.count > 1 {
                    Text("CPU by Node")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)

                    Chart(nodeMetrics) { nm in
                        BarMark(
                            x: .value("CPU", nm.cpuCores),
                            y: .value("Node", nm.name)
                        )
                        .foregroundStyle(.blue.gradient)
                    }
                    .chartXAxisLabel("Cores")
                    .frame(height: CGFloat(nodeMetrics.count * 30 + 30))

                    Text("Memory by Node")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)

                    Chart(nodeMetrics) { nm in
                        BarMark(
                            x: .value("Memory", nm.memoryBytes / (1024 * 1024 * 1024)),
                            y: .value("Node", nm.name)
                        )
                        .foregroundStyle(.purple.gradient)
                    }
                    .chartXAxisLabel("GiB")
                    .frame(height: CGFloat(nodeMetrics.count * 30 + 30))
                }
            }
        }
    }

    // MARK: - Events Section

    @ViewBuilder
    private func eventsSection(for clusterId: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Recent Events")
                    .font(.headline)
                Spacer()
                if isLoadingEvents {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if clusterEvents.isEmpty && !isLoadingEvents {
                Text("No recent events")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(clusterEvents.prefix(20), id: \.id) { event in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: event.type == "Warning" ? "exclamationmark.triangle.fill" : "info.circle.fill")
                            .font(.caption)
                            .foregroundStyle(event.type == "Warning" ? .orange : .blue)
                            .frame(width: 16)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(event.involvedObject?.kind ?? "")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                Text(event.involvedObject?.name ?? "")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(event.age)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            if let msg = event.message {
                                Text(msg)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                    .padding(.vertical, 2)

                    if event.id != clusterEvents.prefix(20).last?.id {
                        Divider()
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func statusColor(_ status: ConnectionStatus) -> Color {
        switch status {
        case .disconnected: return .gray
        case .connecting: return .orange
        case .connected: return .green
        case .error: return .red
        }
    }

    private func statusText(_ status: ConnectionStatus) -> String {
        switch status {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting"
        case .connected(let version): return "v\(version)"
        case .error: return "Error"
        }
    }

    private func utilizationGradient(_ percent: Double) -> some ShapeStyle {
        if percent > 0.9 { return Color.red }
        if percent > 0.7 { return Color.orange }
        return Color.green
    }

    // MARK: - Data Loading

    private func loadOverviewData() {
        // Fetch overview resources for all connected clusters
        for clusterId in viewModel.selectedClusterIds {
            guard let client = viewModel.activeClients[clusterId] else { continue }

            // Load nodes if not already loaded
            if viewModel.nodes[clusterId] == nil || viewModel.nodes[clusterId]?.isEmpty == true {
                Task {
                    do {
                        let nodeList = try await client.list(Node.self, resourceType: .nodes)
                        await MainActor.run { viewModel.nodes[clusterId] = nodeList }
                    } catch {}
                }
            }

            // Load pods for summary if needed
            if viewModel.pods[clusterId] == nil || viewModel.pods[clusterId]?.isEmpty == true {
                Task {
                    do {
                        let podList = try await client.list(Pod.self, resourceType: .pods, namespace: viewModel.selectedNamespace)
                        await MainActor.run { viewModel.pods[clusterId] = podList }
                    } catch {}
                }
            }

            // Load deployments for summary
            if viewModel.deployments[clusterId] == nil || viewModel.deployments[clusterId]?.isEmpty == true {
                Task {
                    do {
                        let depList = try await client.list(Deployment.self, resourceType: .deployments, namespace: viewModel.selectedNamespace)
                        await MainActor.run { viewModel.deployments[clusterId] = depList }
                    } catch {}
                }
            }

            // Load services for summary
            if viewModel.services[clusterId] == nil || viewModel.services[clusterId]?.isEmpty == true {
                Task {
                    do {
                        let svcList = try await client.list(Service.self, resourceType: .services, namespace: viewModel.selectedNamespace)
                        await MainActor.run { viewModel.services[clusterId] = svcList }
                    } catch {}
                }
            }

            // Fetch metrics
            Task { await viewModel.fetchMetrics(for: clusterId) }

            // Fetch events
            loadEvents(for: clusterId)
        }
    }

    private func loadEvents(for clusterId: String) {
        guard let client = viewModel.activeClients[clusterId] else { return }
        isLoadingEvents = true
        Task {
            do {
                let events = try await client.listEvents(namespace: nil)
                let sorted = events.sorted { e1, e2 in
                    (e1.metadata.creationTimestamp ?? .distantPast) > (e2.metadata.creationTimestamp ?? .distantPast)
                }
                await MainActor.run {
                    clusterEvents = sorted
                    isLoadingEvents = false
                }
            } catch {
                await MainActor.run { isLoadingEvents = false }
            }
        }
    }

    private func startAutoRefresh() {
        refreshTimer?.cancel()
        refreshTimer = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled else { break }
                loadOverviewData()
            }
        }
    }
}
