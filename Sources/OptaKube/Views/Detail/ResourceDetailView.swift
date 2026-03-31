import SwiftUI
import AppKit
import Yams

struct ResourceDetailView: View {
    @Environment(AppViewModel.self) private var viewModel
    let resource: ResourceIdentifier
    @State private var selectedTabId: String = "overview"
    @State private var yamlContent: String = ""
    @State private var highlightedYAML: AttributedString?
    @State private var isLoadingYAML = false
    @State private var isEditing = false
    @State private var editContent: String = ""
    @State private var applyError: String?
    @State private var applySuccess = false
    @State private var isApplying = false

    struct TabItem: Identifiable, Hashable {
        let id: String
        let label: String
        let isContainer: Bool

        init(_ id: String, label: String, isContainer: Bool = false) {
            self.id = id
            self.label = label
            self.isContainer = isContainer
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: resource.resourceType.systemImage)
                    .font(.title2)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading) {
                    Text(resource.name)
                        .font(.title2)
                        .fontWeight(.semibold)
                    if let ns = resource.namespace {
                        Text(ns)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()

                // Open logs button (pods only)
                if resource.resourceType == .pods {
                    Button {
                        NotificationCenter.default.post(name: .openFullLogs, object: resource)
                    } label: {
                        Label("Logs", systemImage: "doc.text")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                // Quick actions
                QuickActionsMenu(resource: resource)
            }
            .padding()

            // Tab bar
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(availableTabs) { tab in
                        Button {
                            selectedTabId = tab.id
                        } label: {
                            Text(tab.label)
                                .font(.subheadline)
                                .fontWeight(selectedTabId == tab.id ? .semibold : .regular)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(selectedTabId == tab.id ? Color.accentColor.opacity(0.15) : Color.clear)
                                .foregroundStyle(selectedTabId == tab.id ? Color.accentColor : .secondary)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.bottom, 4)

            Divider()

            // Content
            if selectedTabId == "overview" {
                overviewContent
            } else if selectedTabId == "events" {
                EventsListView(resource: resource)
            } else if selectedTabId == "yaml" {
                yamlTabContent
            } else if selectedTabId.hasPrefix("container:") {
                let containerName = String(selectedTabId.dropFirst("container:".count))
                if let pod = findPod() {
                    containerDetailTab(pod: pod, containerName: containerName)
                }
            }
        }
        .onChange(of: resource) { _, newValue in
            selectedTabId = "overview"
            isEditing = false
            applyError = nil
            applySuccess = false
            loadYAML()
        }
        .onAppear { loadYAML() }
    }

    private var availableTabs: [TabItem] {
        var tabs: [TabItem] = [TabItem("overview", label: "Overview")]
        if resource.resourceType == .pods, let pod = findPod(),
           let containers = pod.spec?.containers {
            for container in containers {
                tabs.append(TabItem("container:\(container.name)", label: container.name, isContainer: true))
            }
        }
        tabs.append(TabItem("events", label: "Events"))
        tabs.append(TabItem("yaml", label: "YAML"))
        return tabs
    }

    // MARK: - Overview

    @ViewBuilder
    private var overviewContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                switch resource.resourceType {
                case .pods:
                    if let pod = findPod() { PodDetailContent(pod: pod) }
                case .deployments:
                    if let dep = findDeployment() { DeploymentDetailContent(deployment: dep) }
                case .services:
                    if let svc = findService() { ServiceDetailContent(service: svc) }
                case .nodes:
                    if let node = findNode() { NodeDetailContent(node: node) }
                case .statefulSets:
                    if let sts = findResource(\.statefulSets) { StatefulSetDetailContent(statefulSet: sts) }
                case .daemonSets:
                    if let ds = findResource(\.daemonSets) { DaemonSetDetailContent(daemonSet: ds) }
                case .replicaSets:
                    if let rs = findResource(\.replicaSets) { ReplicaSetDetailContent(replicaSet: rs) }
                case .jobs:
                    if let job = findResource(\.jobs) { JobDetailContent(job: job) }
                case .cronJobs:
                    if let cj = findResource(\.cronJobs) { CronJobDetailContent(cronJob: cj) }
                case .configMaps:
                    if let cm = findResource(\.configMaps) { ConfigMapDetailContent(configMap: cm) }
                case .secrets:
                    if let secret = findResource(\.secrets) { SecretDetailContent(secret: secret) }
                case .ingresses, .ingressClasses, .persistentVolumes, .persistentVolumeClaims,
                     .networkPolicies, .serviceAccounts, .horizontalPodAutoscalers, .namespaces, .endpoints:
                    Text("Detail view not yet available for \(resource.resourceType.displayName)")
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
    }

    // MARK: - Container Detail Tab

    @ViewBuilder
    private func containerDetailTab(pod: Pod, containerName: String) -> some View {
        let container = pod.spec?.containers?.first(where: { $0.name == containerName })
            ?? pod.spec?.initContainers?.first(where: { $0.name == containerName })
        let status = pod.status?.containerStatuses?.first(where: { $0.name == containerName })
            ?? pod.status?.initContainerStatuses?.first(where: { $0.name == containerName })

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let container = container {
                    // Status
                    DetailSection("Status") {
                        VStack(alignment: .leading, spacing: 4) {
                            if let state = status?.state {
                                HStack(spacing: 6) {
                                    Text("State:")
                                        .foregroundStyle(.secondary)
                                    if state.running != nil {
                                        Text("Running")
                                            .foregroundStyle(.green)
                                            .fontWeight(.medium)
                                    } else if let waiting = state.waiting {
                                        Text("Waiting")
                                            .foregroundStyle(.orange)
                                            .fontWeight(.medium)
                                        if let reason = waiting.reason {
                                            Text("(\(reason))")
                                                .foregroundStyle(.secondary)
                                        }
                                    } else if let terminated = state.terminated {
                                        Text("Terminated")
                                            .foregroundStyle(.red)
                                            .fontWeight(.medium)
                                        if let reason = terminated.reason {
                                            Text("(\(reason))")
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                .font(.system(.body, design: .monospaced))
                            }
                            if let ready = status?.ready {
                                DetailRow(label: "Ready", value: ready ? "Yes" : "No")
                            }
                            if let restarts = status?.restartCount {
                                DetailRow(label: "Restarts", value: "\(restarts)")
                            }
                            if let lastState = status?.lastState {
                                if let terminated = lastState.terminated {
                                    DetailRow(label: "Last Restart", value: terminated.reason ?? "Terminated (exit \(terminated.exitCode ?? -1))")
                                }
                            }
                        }
                    }

                    // Image
                    if let image = container.image {
                        DetailSection("Image") {
                            Text(image)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .background(.quaternary.opacity(0.5))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }

                    // Ports
                    if let ports = container.ports, !ports.isEmpty {
                        DetailSection("Ports") {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(ports, id: \.containerPort) { port in
                                    HStack {
                                        Text("\(port.containerPort)")
                                            .font(.system(.body, design: .monospaced))
                                            .fontWeight(.medium)
                                        Text("/\(port.protocol ?? "TCP")")
                                            .foregroundStyle(.secondary)
                                        if let name = port.name {
                                            Text("(\(name))")
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Environment Variables
                    ContainerEnvSection(container: container, clusterId: resource.clusterId, namespace: resource.namespace)

                    // Resources
                    if let res = container.resources {
                        DetailSection("Resources") {
                            VStack(alignment: .leading, spacing: 4) {
                                if let requests = res.requests, !requests.isEmpty {
                                    Text("Requests")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .fontWeight(.semibold)
                                    ForEach(requests.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                                        DetailRow(label: key, value: value)
                                    }
                                }
                                if let limits = res.limits, !limits.isEmpty {
                                    Text("Limits")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .fontWeight(.semibold)
                                        .padding(.top, 4)
                                    ForEach(limits.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                                        DetailRow(label: key, value: value)
                                    }
                                }
                            }
                        }
                    }

                    // Volume Mounts
                    if let mounts = container.volumeMounts, !mounts.isEmpty {
                        DetailSection("Volume Mounts") {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(mounts, id: \.name) { mount in
                                    HStack {
                                        Text(mount.name)
                                            .font(.system(.caption, design: .monospaced))
                                            .fontWeight(.medium)
                                        Image(systemName: "arrow.right")
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                        Text(mount.mountPath)
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                        if mount.readOnly == true {
                                            Text("RO")
                                                .font(.caption2)
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 1)
                                                .background(.orange.opacity(0.2))
                                                .clipShape(RoundedRectangle(cornerRadius: 3))
                                                .foregroundStyle(.orange)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Probes
                    if let probe = container.livenessProbe {
                        probeCard(title: "Liveness Probe", probe: probe)
                    }
                    if let probe = container.readinessProbe {
                        probeCard(title: "Readiness Probe", probe: probe)
                    }
                    if let probe = container.startupProbe {
                        probeCard(title: "Startup Probe", probe: probe)
                    }
                } else {
                    Text("Container not found")
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
    }

    @ViewBuilder
    private func probeCard(title: String, probe: Probe) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "heart.text.square")
                    .foregroundStyle(.teal)
                Text(title)
                    .font(.headline)
                Spacer()
                Text(probe.methodType)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.teal.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .foregroundStyle(.teal)
            }

            Text(probe.methodDescription)
                .font(.system(.subheadline, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(.quaternary.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 4))

            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(probe.timingDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 4) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(probe.thresholdDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - YAML Tab

    @ViewBuilder
    private var yamlTabContent: some View {
        if isLoadingYAML {
            ProgressView("Loading YAML...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if isEditing {
            yamlEditorView
        } else {
            yamlReadOnlyView
        }
    }

    @ViewBuilder
    private var yamlReadOnlyView: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                if applySuccess {
                    Label("Applied successfully", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                }
                Button("Edit") {
                    editContent = yamlContent
                    isEditing = true
                    applyError = nil
                    applySuccess = false
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal)
            .padding(.vertical, 4)

            ScrollView {
                if let highlighted = highlightedYAML {
                    Text(highlighted)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                } else {
                    // Plain fallback while highlighting is computed
                    Text(yamlContent)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
            }
        }
    }

    @ViewBuilder
    private var yamlEditorView: some View {
        VStack(spacing: 0) {
            HStack {
                if let error = applyError {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                        .lineLimit(2)
                }
                Spacer()
                Button("Cancel") {
                    isEditing = false
                    applyError = nil
                }
                .buttonStyle(.bordered)

                Button("Apply") {
                    applyChanges()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isApplying)
            }
            .padding(.horizontal)
            .padding(.vertical, 4)

            if isApplying {
                ProgressView()
                    .padding(4)
            }

            TextEditor(text: $editContent)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(4)
        }
    }

    // MARK: - YAML Syntax Highlighting

    private func syntaxHighlightedYAML(_ yaml: String) -> AttributedString {
        var result = AttributedString()
        let lines = yaml.split(separator: "\n", omittingEmptySubsequences: false)
        for (index, line) in lines.enumerated() {
            let lineStr = String(line)
            if index > 0 {
                var newline = AttributedString("\n")
                newline.font = .system(.body, design: .monospaced)
                result.append(newline)
            }

            if lineStr.trimmingCharacters(in: .whitespaces).hasPrefix("#") {
                // Comment
                var attr = AttributedString(lineStr)
                attr.font = .system(.body, design: .monospaced)
                attr.foregroundColor = .gray
                result.append(attr)
            } else if lineStr.trimmingCharacters(in: .whitespaces).hasPrefix("- ") {
                // List item
                if let dashRange = lineStr.range(of: "- ") {
                    let indent = String(lineStr[lineStr.startIndex..<dashRange.lowerBound])
                    var indentAttr = AttributedString(indent)
                    indentAttr.font = .system(.body, design: .monospaced)
                    result.append(indentAttr)

                    var dashAttr = AttributedString("- ")
                    dashAttr.font = .system(.body, design: .monospaced)
                    dashAttr.foregroundColor = .gray
                    result.append(dashAttr)

                    let rest = String(lineStr[dashRange.upperBound...])
                    result.append(highlightYAMLKeyValue(rest))
                } else {
                    result.append(highlightYAMLKeyValue(lineStr))
                }
            } else {
                result.append(highlightYAMLKeyValue(lineStr))
            }
        }
        return result
    }

    private func highlightYAMLKeyValue(_ line: String) -> AttributedString {
        var result = AttributedString()
        if let colonIdx = line.firstIndex(of: ":") {
            let key = String(line[line.startIndex...colonIdx])
            var keyAttr = AttributedString(key)
            keyAttr.font = .system(.body, design: .monospaced)
            keyAttr.foregroundColor = .teal
            result.append(keyAttr)

            let afterColon = line.index(after: colonIdx)
            if afterColon < line.endIndex {
                let value = String(line[afterColon...]).trimmingCharacters(in: .whitespaces)
                var spaceAttr = AttributedString(" ")
                spaceAttr.font = .system(.body, design: .monospaced)
                result.append(spaceAttr)

                var valAttr = AttributedString(value)
                valAttr.font = .system(.body, design: .monospaced)
                if value == "true" || value == "false" || value == "null" || value == "~" {
                    valAttr.foregroundColor = .purple
                } else if value.hasPrefix("'") || value.hasPrefix("\"") {
                    valAttr.foregroundColor = .green
                } else if let _ = Double(value) {
                    valAttr.foregroundColor = .orange
                } else {
                    valAttr.foregroundColor = .green
                }
                result.append(valAttr)
            }
        } else {
            var attr = AttributedString(line)
            attr.font = .system(.body, design: .monospaced)
            attr.foregroundColor = .primary
            result.append(attr)
        }
        return result
    }

    // MARK: - Apply Changes

    private func applyChanges() {
        guard let client = viewModel.activeClients[resource.clusterId] else { return }
        // Try to parse as YAML first, then convert to JSON for the API
        let bodyData: Data
        do {
            if let yamlObj = try Yams.load(yaml: editContent) {
                bodyData = try JSONSerialization.data(withJSONObject: yamlObj)
            } else {
                applyError = "Empty YAML content"
                return
            }
        } catch {
            // Fallback: try as raw JSON
            guard let rawData = editContent.data(using: .utf8),
                  (try? JSONSerialization.jsonObject(with: rawData)) != nil else {
                applyError = "Invalid YAML: \(error.localizedDescription)"
                return
            }
            bodyData = rawData
        }
        isApplying = true
        applyError = nil
        Task {
            do {
                try await client.replace(
                    resourceType: resource.resourceType,
                    name: resource.name,
                    namespace: resource.namespace,
                    body: bodyData
                )
                await MainActor.run {
                    yamlContent = editContent
                    isEditing = false
                    isApplying = false
                    applySuccess = true
                }
                // Reload to get server-side changes
                loadYAML()
            } catch {
                await MainActor.run {
                    applyError = error.localizedDescription
                    isApplying = false
                }
            }
        }
    }

    // MARK: - Load YAML

    private func loadYAML() {
        guard let client = viewModel.activeClients[resource.clusterId] else { return }
        isLoadingYAML = true
        highlightedYAML = nil
        Task {
            do {
                let data = try await client.getRawYAML(
                    resourceType: resource.resourceType,
                    name: resource.name,
                    namespace: resource.namespace
                )
                if let json = try? JSONSerialization.jsonObject(with: data) {
                    // Convert JSON to YAML using Yams
                    let yamlStr: String
                    do {
                        yamlStr = try Yams.dump(object: json, sortKeys: true)
                    } catch {
                        // Fallback to pretty JSON if YAML conversion fails
                        if let prettyData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
                           let pretty = String(data: prettyData, encoding: .utf8) {
                            yamlStr = pretty
                        } else {
                            yamlStr = String(data: data, encoding: .utf8) ?? ""
                        }
                    }
                    await MainActor.run {
                        yamlContent = yamlStr
                        isLoadingYAML = false
                    }
                    // Compute highlighting in background
                    let highlighted = syntaxHighlightedYAML(yamlStr)
                    await MainActor.run {
                        highlightedYAML = highlighted
                    }
                }
            } catch {
                await MainActor.run {
                    yamlContent = "Error: \(error.localizedDescription)"
                    isLoadingYAML = false
                }
            }
        }
    }

    // MARK: - Find Resources

    private func findPod() -> Pod? { findResource(\.pods) }
    private func findDeployment() -> Deployment? { findResource(\.deployments) }
    private func findService() -> Service? { findResource(\.services) }
    private func findNode() -> Node? { findResource(\.nodes) }

    private func findResource<T: K8sResource>(_ keyPath: KeyPath<AppViewModel, [String: [T]]>) -> T? {
        viewModel[keyPath: keyPath][resource.clusterId]?.first {
            $0.name == resource.name && (resource.namespace == nil || $0.metadata.namespace == resource.namespace)
        }
    }
}

// MARK: - Detail Content Views

struct DetailSection: View {
    let title: String
    let content: () -> AnyView

    init(_ title: String, @ViewBuilder content: @escaping () -> some View) {
        self.title = title
        self.content = { AnyView(content()) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            content()
        }
    }
}

struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 140, alignment: .trailing)
            Text(value)
                .textSelection(.enabled)
            Spacer()
        }
        .font(.system(.body, design: .monospaced))
    }
}

struct PodDetailContent: View {
    @Environment(AppViewModel.self) private var viewModel
    let pod: Pod

    var body: some View {
        DetailSection("Status") {
            VStack(alignment: .leading, spacing: 4) {
                DetailRow(label: "Phase", value: pod.phase)
                DetailRow(label: "Pod IP", value: pod.podIP)
                DetailRow(label: "Host IP", value: pod.hostIP)
                DetailRow(label: "Node", value: pod.nodeName)
                DetailRow(label: "Restarts", value: "\(pod.restartCount)")
                DetailRow(label: "Ready", value: "\(pod.readyCount)/\(pod.totalContainers)")
            }
        }

        // Metrics section
        if let clusterId = viewModel.selectedClusterIds.first {
            DetailSection("Metrics") {
                PodMetricsView(
                    podName: pod.name,
                    namespace: pod.metadata.namespace,
                    clusterId: clusterId
                )
            }
        }

        if let containers = pod.spec?.containers, !containers.isEmpty {
            DetailSection("Containers") {
                ForEach(containers) { container in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(container.name)
                            .fontWeight(.medium)
                        if let image = container.image {
                            DetailRow(label: "Image", value: image)
                        }
                        if let ports = container.ports, !ports.isEmpty {
                            DetailRow(label: "Ports", value: ports.map { "\($0.containerPort)/\($0.protocol ?? "TCP")" }.joined(separator: ", "))
                        }
                    }
                    .padding(8)
                    .background(.quaternary.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
        }

        if let conditions = pod.status?.conditions, !conditions.isEmpty {
            DetailSection("Conditions") {
                ForEach(conditions, id: \.type) { condition in
                    HStack {
                        Image(systemName: condition.status == "True" ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(condition.status == "True" ? .green : .red)
                        Text(condition.type)
                        Spacer()
                        if let reason = condition.reason {
                            Text(reason)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}

struct DeploymentDetailContent: View {
    let deployment: Deployment

    var body: some View {
        DetailSection("Status") {
            VStack(alignment: .leading, spacing: 4) {
                DetailRow(label: "Replicas", value: "\(deployment.replicas)")
                DetailRow(label: "Ready", value: "\(deployment.readyReplicas)")
                DetailRow(label: "Up-to-date", value: "\(deployment.updatedReplicas)")
                DetailRow(label: "Available", value: "\(deployment.availableReplicas)")
                if let strategy = deployment.spec?.strategy?.type {
                    DetailRow(label: "Strategy", value: strategy)
                }
            }
        }

        if let conditions = deployment.status?.conditions, !conditions.isEmpty {
            DetailSection("Conditions") {
                ForEach(conditions, id: \.type) { condition in
                    HStack {
                        Image(systemName: condition.status == "True" ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(condition.status == "True" ? .green : .red)
                        Text(condition.type)
                        Spacer()
                        if let msg = condition.message {
                            Text(msg)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
    }
}

struct ServiceDetailContent: View {
    let service: Service

    var body: some View {
        DetailSection("Info") {
            VStack(alignment: .leading, spacing: 4) {
                DetailRow(label: "Type", value: service.serviceType)
                DetailRow(label: "Cluster IP", value: service.clusterIP)
                DetailRow(label: "Ports", value: service.portsDisplay)
                if let selector = service.spec?.selector {
                    DetailRow(label: "Selector", value: selector.map { "\($0.key)=\($0.value)" }.joined(separator: ", "))
                }
            }
        }
    }
}

struct NodeDetailContent: View {
    @Environment(AppViewModel.self) private var viewModel
    let node: Node

    @State private var nodeMetrics: NodeMetrics?
    @State private var metricsError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            DetailSection("Info") {
                VStack(alignment: .leading, spacing: 4) {
                    DetailRow(label: "Roles", value: node.roles)
                    DetailRow(label: "Version", value: node.kubeletVersion)
                    if let info = node.status?.nodeInfo {
                        DetailRow(label: "OS", value: "\(info.operatingSystem ?? "")/\(info.architecture ?? "")")
                        DetailRow(label: "OS Image", value: info.osImage ?? "")
                        DetailRow(label: "Container Runtime", value: info.containerRuntimeVersion ?? "")
                        DetailRow(label: "Kernel", value: info.kernelVersion ?? "")
                    }
                }
            }

            // Metrics section
            if let nm = nodeMetrics {
                DetailSection("Resource Usage") {
                    NodeMetricsView(
                        nodeMetrics: nm,
                        capacity: node.status?.capacity,
                        allocatable: node.status?.allocatable
                    )
                }
            } else if let error = metricsError {
                DetailSection("Resource Usage") {
                    Text("Metrics not available: \(error)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let capacity = node.status?.capacity {
                DetailSection("Capacity") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(capacity.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                            DetailRow(label: key, value: value)
                        }
                    }
                }
            }

            if let conditions = node.status?.conditions, !conditions.isEmpty {
                DetailSection("Conditions") {
                    ForEach(conditions, id: \.type) { condition in
                        HStack {
                            Image(systemName: condition.status == "True" ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(condition.type == "Ready" ? (condition.status == "True" ? .green : .red) : (condition.status == "True" ? .red : .green))
                            Text(condition.type)
                            Spacer()
                            if let reason = condition.reason {
                                Text(reason)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .onAppear { fetchNodeMetrics() }
    }

    private func fetchNodeMetrics() {
        guard let clusterId = viewModel.selectedClusterIds.first,
              let client = viewModel.activeClients[clusterId] else { return }
        Task {
            do {
                let allMetrics = try await client.listNodeMetrics()
                let match = allMetrics.first { $0.name == node.name }
                await MainActor.run { nodeMetrics = match }
            } catch {
                await MainActor.run { metricsError = error.localizedDescription }
            }
        }
    }
}

// MARK: - Container Environment Section (with envFrom + toggleable values)

struct ContainerEnvSection: View {
    @Environment(AppViewModel.self) private var viewModel
    let container: Container
    let clusterId: String
    let namespace: String?
    @State private var revealedVars: Set<String> = []
    @State private var resolvedValues: [String: String] = [:]  // "varName" -> resolved value
    @State private var loadingVars: Set<String> = []
    @State private var showAll = false
    // envFrom expansion
    @State private var expandedSources: Set<String> = []  // "secret:name" or "configmap:name"
    @State private var resolvedSourceKeys: [String: [(key: String, value: String)]] = [:]
    @State private var loadingSources: Set<String> = []

    private var envCount: Int { container.env?.count ?? 0 }
    private var envFromCount: Int { container.envFrom?.count ?? 0 }

    private var totalLabel: String {
        var parts: [String] = []
        if envCount > 0 { parts.append("\(envCount) vars") }
        if envFromCount > 0 { parts.append("\(envFromCount) source\(envFromCount == 1 ? "" : "s")") }
        return parts.joined(separator: " + ")
    }

    var body: some View {
        if envCount > 0 || envFromCount > 0 {
            DetailSection("Environment (\(totalLabel))") {
                // Refresh button to invalidate caches
                HStack {
                    Spacer()
                    if !resolvedValues.isEmpty || !resolvedSourceKeys.isEmpty {
                        Button {
                            resolvedValues.removeAll()
                            resolvedSourceKeys.removeAll()
                            revealedVars.removeAll()
                            expandedSources.removeAll()
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.clockwise")
                                Text("Refresh values")
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                VStack(alignment: .leading, spacing: 0) {
                    // envFrom sources (entire ConfigMap/Secret injected) — expandable
                    if let envFrom = container.envFrom, !envFrom.isEmpty {
                        ForEach(envFrom.indices, id: \.self) { idx in
                            let src = envFrom[idx]
                            let sourceId = envFromSourceId(src)
                            let isExpanded = expandedSources.contains(sourceId)
                            let isLoading = loadingSources.contains(sourceId)

                            VStack(alignment: .leading, spacing: 0) {
                                HStack(spacing: 6) {
                                    // Disclosure indicator
                                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                        .font(.system(size: 8))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 10)

                                    if src.secretRef != nil {
                                        Image(systemName: "lock.fill")
                                            .font(.caption2)
                                            .foregroundStyle(.orange)
                                        Text("Secret: \(src.secretRef?.name ?? "?")")
                                            .font(.system(.caption, design: .monospaced))
                                            .fontWeight(.medium)
                                    } else if src.configMapRef != nil {
                                        Image(systemName: "doc.text")
                                            .font(.caption2)
                                            .foregroundStyle(.blue)
                                        Text("ConfigMap: \(src.configMapRef?.name ?? "?")")
                                            .font(.system(.caption, design: .monospaced))
                                            .fontWeight(.medium)
                                    }

                                    if let prefix = src.prefix, !prefix.isEmpty {
                                        Text("prefix: \(prefix)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    if isLoading {
                                        ProgressView().controlSize(.mini)
                                    } else if let keys = resolvedSourceKeys[sourceId] {
                                        Text("\(keys.count) keys")
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                .padding(.vertical, 4)
                                .padding(.horizontal, 6)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if isExpanded {
                                        expandedSources.remove(sourceId)
                                    } else {
                                        expandedSources.insert(sourceId)
                                        resolveEnvFromSource(src)
                                    }
                                }

                                // Expanded key-value pairs
                                if isExpanded, let keys = resolvedSourceKeys[sourceId] {
                                    VStack(alignment: .leading, spacing: 0) {
                                        ForEach(keys.indices, id: \.self) { ki in
                                            let kv = keys[ki]
                                            HStack(alignment: .top, spacing: 6) {
                                                Text(kv.key)
                                                    .font(.system(.caption2, design: .monospaced))
                                                    .fontWeight(.medium)
                                                    .frame(minWidth: 60, alignment: .trailing)
                                                Text("=")
                                                    .font(.system(.caption2, design: .monospaced))
                                                    .foregroundStyle(.tertiary)
                                                Text(kv.value)
                                                    .font(.system(.caption2, design: .monospaced))
                                                    .foregroundStyle(.secondary)
                                                    .textSelection(.enabled)
                                                    .lineLimit(3)
                                                Spacer()
                                            }
                                            .padding(.vertical, 2)
                                            .padding(.horizontal, 6)
                                            .padding(.leading, 20)
                                            .background(ki % 2 == 0 ? Color.clear : Color.primary.opacity(0.02))
                                        }
                                    }
                                }
                            }
                            .background(idx % 2 == 0 ? Color.clear : Color.primary.opacity(0.02))
                        }

                        if envCount > 0 {
                            Divider().padding(.vertical, 4)
                        }
                    }

                    // Individual env vars
                    if let env = container.env {
                        let visible = showAll ? env : Array(env.prefix(10))
                        ForEach(visible.indices, id: \.self) { idx in
                            envVarRow(visible[idx], idx: idx)
                        }

                        if env.count > 10 && !showAll {
                            Button("Show all \(env.count) variables") {
                                showAll = true
                            }
                            .font(.caption)
                            .padding(.top, 4)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func envVarRow(_ envVar: EnvVar, idx: Int) -> some View {
        let isRevealed = revealedVars.contains(envVar.name)
        let isSecret = envVar.valueFrom?.secretKeyRef != nil

        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                if isSecret {
                    Image(systemName: "lock.fill").font(.system(size: 8)).foregroundStyle(.orange)
                } else if envVar.valueFrom?.configMapKeyRef != nil {
                    Image(systemName: "doc.text").font(.system(size: 8)).foregroundStyle(.blue)
                } else if envVar.valueFrom?.fieldRef != nil {
                    Image(systemName: "arrow.down.circle").font(.system(size: 8)).foregroundStyle(.purple)
                }

                Text(envVar.name)
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.medium)
                    .lineLimit(1)

                Spacer()

                if hasRevealableValue(envVar) {
                    if loadingVars.contains(envVar.name) {
                        ProgressView().controlSize(.mini)
                    } else {
                        Button {
                            if isRevealed {
                                revealedVars.remove(envVar.name)
                            } else {
                                revealedVars.insert(envVar.name)
                                resolveValue(envVar)
                            }
                        } label: {
                            Image(systemName: isRevealed ? "eye.slash" : "eye").font(.system(size: 9))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                }

                sourceBadge(envVar)
            }

            if isRevealed {
                let displayValue = resolvedValues[envVar.name] ?? valueText(envVar)
                Text(displayValue)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(10)
                    .padding(.leading, 16)
                    .padding(.vertical, 2)
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(idx % 2 == 0 ? Color.clear : Color.primary.opacity(0.02))
    }

    // MARK: - envFrom resolution

    private func envFromSourceId(_ src: EnvFromSource) -> String {
        if let s = src.secretRef?.name { return "secret:\(s)" }
        if let c = src.configMapRef?.name { return "configmap:\(c)" }
        return "unknown"
    }

    private func resolveEnvFromSource(_ src: EnvFromSource) {
        let sourceId = envFromSourceId(src)
        guard resolvedSourceKeys[sourceId] == nil else { return }  // already resolved
        guard let client = viewModel.activeClients[clusterId],
              let ns = namespace else { return }

        loadingSources.insert(sourceId)

        if let secretName = src.secretRef?.name {
            Task {
                do {
                    let secret = try await client.get(Secret.self, resourceType: .secrets, name: secretName, namespace: ns)
                    let prefix = src.prefix ?? ""
                    let pairs: [(key: String, value: String)] = (secret.data ?? [:]).sorted(by: { $0.key < $1.key }).map { k, v in
                        let decoded = Data(base64Encoded: v).flatMap { String(data: $0, encoding: .utf8) } ?? v
                        return (key: "\(prefix)\(k)", value: decoded)
                    }
                    await MainActor.run {
                        resolvedSourceKeys[sourceId] = pairs
                        loadingSources.remove(sourceId)
                    }
                } catch {
                    await MainActor.run {
                        resolvedSourceKeys[sourceId] = [(key: "error", value: error.localizedDescription)]
                        loadingSources.remove(sourceId)
                    }
                }
            }
        } else if let cmName = src.configMapRef?.name {
            Task {
                do {
                    let cm = try await client.get(ConfigMap.self, resourceType: .configMaps, name: cmName, namespace: ns)
                    let prefix = src.prefix ?? ""
                    let pairs: [(key: String, value: String)] = (cm.data ?? [:]).sorted(by: { $0.key < $1.key }).map { k, v in
                        (key: "\(prefix)\(k)", value: v)
                    }
                    await MainActor.run {
                        resolvedSourceKeys[sourceId] = pairs
                        loadingSources.remove(sourceId)
                    }
                } catch {
                    await MainActor.run {
                        resolvedSourceKeys[sourceId] = [(key: "error", value: error.localizedDescription)]
                        loadingSources.remove(sourceId)
                    }
                }
            }
        }
    }

    private func hasRevealableValue(_ envVar: EnvVar) -> Bool {
        envVar.value != nil || envVar.valueFrom != nil
    }

    private func valueText(_ envVar: EnvVar) -> String {
        if let val = envVar.value, !val.isEmpty { return val }
        if let s = envVar.valueFrom?.secretKeyRef { return "secret:\(s.name)/\(s.key)" }
        if let c = envVar.valueFrom?.configMapKeyRef { return "configmap:\(c.name)/\(c.key)" }
        if let f = envVar.valueFrom?.fieldRef { return "fieldRef:\(f.fieldPath)" }
        return "(empty)"
    }

    private func resolveValue(_ envVar: EnvVar) {
        // Plain value — already available
        if let val = envVar.value, !val.isEmpty {
            resolvedValues[envVar.name] = val
            return
        }

        guard let client = viewModel.activeClients[clusterId],
              let ns = namespace else { return }

        // Secret key ref — fetch the secret and decode the specific key
        if let secretRef = envVar.valueFrom?.secretKeyRef {
            loadingVars.insert(envVar.name)
            Task {
                do {
                    let secret = try await client.get(Secret.self, resourceType: .secrets, name: secretRef.name, namespace: ns)
                    if let b64 = secret.data?[secretRef.key],
                       let decoded = Data(base64Encoded: b64),
                       let value = String(data: decoded, encoding: .utf8) {
                        await MainActor.run {
                            resolvedValues[envVar.name] = value
                            loadingVars.remove(envVar.name)
                        }
                    } else {
                        await MainActor.run {
                            resolvedValues[envVar.name] = "(key '\(secretRef.key)' not found in secret)"
                            loadingVars.remove(envVar.name)
                        }
                    }
                } catch {
                    await MainActor.run {
                        resolvedValues[envVar.name] = "Error: \(error.localizedDescription)"
                        loadingVars.remove(envVar.name)
                    }
                }
            }
            return
        }

        // ConfigMap key ref — fetch the configmap and get the specific key
        if let cmRef = envVar.valueFrom?.configMapKeyRef {
            loadingVars.insert(envVar.name)
            Task {
                do {
                    let cm = try await client.get(ConfigMap.self, resourceType: .configMaps, name: cmRef.name, namespace: ns)
                    if let value = cm.data?[cmRef.key] {
                        await MainActor.run {
                            resolvedValues[envVar.name] = value
                            loadingVars.remove(envVar.name)
                        }
                    } else {
                        await MainActor.run {
                            resolvedValues[envVar.name] = "(key '\(cmRef.key)' not found in configmap)"
                            loadingVars.remove(envVar.name)
                        }
                    }
                } catch {
                    await MainActor.run {
                        resolvedValues[envVar.name] = "Error: \(error.localizedDescription)"
                        loadingVars.remove(envVar.name)
                    }
                }
            }
            return
        }

        // Field ref — just show the field path
        if let fieldRef = envVar.valueFrom?.fieldRef {
            resolvedValues[envVar.name] = "fieldRef:\(fieldRef.fieldPath)"
        }
    }

    @ViewBuilder
    private func sourceBadge(_ envVar: EnvVar) -> some View {
        if let s = envVar.valueFrom?.secretKeyRef {
            Text("\(s.name)/\(s.key)")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.orange.opacity(0.8))
                .lineLimit(1)
        } else if let c = envVar.valueFrom?.configMapKeyRef {
            Text("\(c.name)/\(c.key)")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.blue.opacity(0.8))
                .lineLimit(1)
        } else if let f = envVar.valueFrom?.fieldRef {
            Text(f.fieldPath)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.purple.opacity(0.8))
                .lineLimit(1)
        }
    }
}
