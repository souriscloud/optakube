import SwiftUI

// MARK: - StatefulSet

struct StatefulSetDetailContent: View {
    let statefulSet: StatefulSet

    var body: some View {
        DetailSection("Status") {
            VStack(alignment: .leading, spacing: 4) {
                DetailRow(label: "Replicas", value: "\(statefulSet.replicas)")
                DetailRow(label: "Ready", value: "\(statefulSet.readyReplicas)")
                if let svc = statefulSet.spec?.serviceName {
                    DetailRow(label: "Service Name", value: svc)
                }
            }
        }

        if let selector = statefulSet.spec?.selector?.matchLabels, !selector.isEmpty {
            DetailSection("Selector") {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(selector.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                        DetailRow(label: key, value: value)
                    }
                }
            }
        }
    }
}

// MARK: - DaemonSet

struct DaemonSetDetailContent: View {
    let daemonSet: DaemonSet

    var body: some View {
        DetailSection("Status") {
            VStack(alignment: .leading, spacing: 4) {
                DetailRow(label: "Desired", value: "\(daemonSet.desiredNumberScheduled)")
                DetailRow(label: "Ready", value: "\(daemonSet.numberReady)")
                if let available = daemonSet.status?.numberAvailable {
                    DetailRow(label: "Available", value: "\(available)")
                }
                if let misscheduled = daemonSet.status?.numberMisscheduled, misscheduled > 0 {
                    DetailRow(label: "Misscheduled", value: "\(misscheduled)")
                }
            }
        }

        if let selector = daemonSet.spec?.selector?.matchLabels, !selector.isEmpty {
            DetailSection("Selector") {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(selector.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                        DetailRow(label: key, value: value)
                    }
                }
            }
        }
    }
}

// MARK: - ReplicaSet

struct ReplicaSetDetailContent: View {
    let replicaSet: ReplicaSet

    var body: some View {
        DetailSection("Status") {
            VStack(alignment: .leading, spacing: 4) {
                DetailRow(label: "Replicas", value: "\(replicaSet.replicas)")
                DetailRow(label: "Ready", value: "\(replicaSet.readyReplicas)")
                if let available = replicaSet.status?.availableReplicas {
                    DetailRow(label: "Available", value: "\(available)")
                }
            }
        }

        if let owners = replicaSet.metadata.ownerReferences, !owners.isEmpty {
            DetailSection("Owner") {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(owners, id: \.uid) { owner in
                        DetailRow(label: owner.kind, value: owner.name)
                    }
                }
            }
        }
    }
}

// MARK: - Job

struct JobDetailContent: View {
    let job: Job

    var body: some View {
        DetailSection("Status") {
            VStack(alignment: .leading, spacing: 4) {
                DetailRow(label: "Completions", value: "\(job.succeeded)/\(job.completions)")
                DetailRow(label: "Duration", value: job.duration)
                if let active = job.status?.active {
                    DetailRow(label: "Active", value: "\(active)")
                }
                if let failed = job.status?.failed {
                    DetailRow(label: "Failed", value: "\(failed)")
                }
                if let parallelism = job.spec?.parallelism {
                    DetailRow(label: "Parallelism", value: "\(parallelism)")
                }
                if let backoffLimit = job.spec?.backoffLimit {
                    DetailRow(label: "Backoff Limit", value: "\(backoffLimit)")
                }
            }
        }

        if let conditions = job.status?.conditions, !conditions.isEmpty {
            DetailSection("Conditions") {
                ForEach(conditions, id: \.type) { condition in
                    HStack {
                        Image(systemName: condition.status == "True" ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(condition.status == "True" ? .green : .red)
                        Text(condition.type)
                        Spacer()
                        if let reason = condition.reason {
                            Text(reason).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - CronJob

struct CronJobDetailContent: View {
    let cronJob: CronJob

    var body: some View {
        DetailSection("Schedule") {
            VStack(alignment: .leading, spacing: 4) {
                DetailRow(label: "Schedule", value: cronJob.schedule)
                DetailRow(label: "Suspended", value: cronJob.isSuspended ? "Yes" : "No")
                if let policy = cronJob.spec?.concurrencyPolicy {
                    DetailRow(label: "Concurrency", value: policy)
                }
                DetailRow(label: "Last Scheduled", value: cronJob.lastScheduleDisplay)
                if let activeJobs = cronJob.status?.active {
                    DetailRow(label: "Active Jobs", value: "\(activeJobs.count)")
                }
            }
        }
    }
}

// MARK: - ConfigMap

struct ConfigMapDetailContent: View {
    let configMap: ConfigMap

    var body: some View {
        if let data = configMap.data, !data.isEmpty {
            DetailSection("Data (\(data.count) keys)") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(data.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(key)
                                .fontWeight(.medium)
                                .font(.subheadline)
                            Text(value)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .lineLimit(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(6)
                                .background(.quaternary.opacity(0.5))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                }
            }
        } else {
            Text("No data")
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Secret

struct SecretDetailContent: View {
    let secret: Secret
    @State private var revealedKeys: Set<String> = []

    var body: some View {
        DetailSection("Info") {
            DetailRow(label: "Type", value: secret.secretType)
        }

        if let data = secret.data, !data.isEmpty {
            DetailSection("Data (\(data.count) keys)") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(data.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(key)
                                    .fontWeight(.medium)
                                    .font(.subheadline)
                                Spacer()
                                Button {
                                    if revealedKeys.contains(key) {
                                        revealedKeys.remove(key)
                                    } else {
                                        revealedKeys.insert(key)
                                    }
                                } label: {
                                    Image(systemName: revealedKeys.contains(key) ? "eye.slash" : "eye")
                                        .font(.caption)
                                }
                                .buttonStyle(.borderless)
                            }

                            if revealedKeys.contains(key) {
                                let decoded = Data(base64Encoded: value).flatMap { String(data: $0, encoding: .utf8) } ?? value
                                Text(decoded)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                                    .lineLimit(10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(6)
                                    .background(.quaternary.opacity(0.5))
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            } else {
                                Text(String(repeating: "*", count: 12))
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }
        } else {
            Text("No data")
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Ingress

struct IngressDetailContent: View {
    let ingress: Ingress

    var body: some View {
        DetailSection("Info") {
            VStack(alignment: .leading, spacing: 4) {
                DetailRow(label: "Class", value: ingress.ingressClassName.isEmpty ? "—" : ingress.ingressClassName)
                DetailRow(label: "Load Balancer", value: loadBalancerDisplay)
                DetailRow(label: "TLS", value: ingress.tlsEnabled ? "Enabled" : "Disabled")
                if let backend = ingress.spec?.defaultBackend {
                    DetailRow(label: "Default Backend", value: backendDisplay(backend))
                }
            }
        }

        let rules = ingress.spec?.rules ?? []
        DetailSection("Rules (\(rules.count))") {
            if rules.isEmpty {
                Text("None")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(rules.enumerated()), id: \.offset) { _, rule in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(rule.host ?? "(any host)")
                                .fontWeight(.medium)
                            let paths = rule.http?.paths ?? []
                            if paths.isEmpty {
                                DetailRow(label: "Paths", value: "None")
                            } else {
                                ForEach(Array(paths.enumerated()), id: \.offset) { _, path in
                                    DetailRow(label: path.path ?? "/", value: backendDisplay(path.backend))
                                }
                            }
                        }
                        .padding(8)
                        .background(.quaternary.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
        }

        if let tls = ingress.spec?.tls, !tls.isEmpty {
            DetailSection("TLS") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(tls.enumerated()), id: \.offset) { _, entry in
                        VStack(alignment: .leading, spacing: 4) {
                            DetailRow(label: "Secret", value: entry.secretName ?? "—")
                            let hosts = entry.hosts ?? []
                            DetailRow(label: "Hosts", value: hosts.isEmpty ? "(all)" : hosts.joined(separator: ", "))
                        }
                    }
                }
            }
        }
    }

    private var loadBalancerDisplay: String {
        let addresses = (ingress.status?.loadBalancer?.ingress ?? []).compactMap { $0.ip ?? $0.hostname }
        return addresses.isEmpty ? "Pending" : addresses.joined(separator: ", ")
    }

    private func backendDisplay(_ backend: IngressBackend?) -> String {
        guard let service = backend?.service else { return "—" }
        if let number = service.port?.number { return "\(service.name):\(number)" }
        if let name = service.port?.name { return "\(service.name):\(name)" }
        return service.name
    }
}

// MARK: - IngressClass

struct IngressClassDetailContent: View {
    let ingressClass: IngressClass

    var body: some View {
        DetailSection("Info") {
            VStack(alignment: .leading, spacing: 4) {
                DetailRow(label: "Controller", value: ingressClass.controller.isEmpty ? "—" : ingressClass.controller)
                DetailRow(label: "Default Class", value: ingressClass.isDefault ? "Yes" : "No")
            }
        }

        if let parameters = ingressClass.spec?.parameters {
            DetailSection("Parameters") {
                VStack(alignment: .leading, spacing: 4) {
                    DetailRow(label: "Kind", value: parameters.kind ?? "—")
                    DetailRow(label: "Name", value: parameters.name ?? "—")
                    if let group = parameters.apiGroup, !group.isEmpty {
                        DetailRow(label: "API Group", value: group)
                    }
                }
            }
        }
    }
}

// MARK: - PersistentVolume

struct PersistentVolumeDetailContent: View {
    let volume: PersistentVolume

    var body: some View {
        DetailSection("Status") {
            VStack(alignment: .leading, spacing: 4) {
                DetailRow(label: "Phase", value: volume.phase)
                DetailRow(label: "Capacity", value: volume.capacity.isEmpty ? "—" : volume.capacity)
                DetailRow(label: "Access Modes", value: volume.accessModesDisplay.isEmpty ? "—" : volume.accessModesDisplay)
                DetailRow(label: "Reclaim Policy", value: volume.reclaimPolicy.isEmpty ? "—" : volume.reclaimPolicy)
                DetailRow(label: "Storage Class", value: volume.storageClassName.isEmpty ? "—" : volume.storageClassName)
            }
        }

        DetailSection("Claim") {
            if let claim = volume.spec?.claimRef {
                VStack(alignment: .leading, spacing: 4) {
                    DetailRow(label: "Name", value: claim.name ?? "—")
                    DetailRow(label: "Namespace", value: claim.namespace ?? "—")
                }
            } else {
                Text("Not bound")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - PersistentVolumeClaim

struct PersistentVolumeClaimDetailContent: View {
    let claim: PersistentVolumeClaim

    var body: some View {
        DetailSection("Status") {
            VStack(alignment: .leading, spacing: 4) {
                DetailRow(label: "Phase", value: claim.phase)
                DetailRow(label: "Capacity", value: claim.capacity.isEmpty ? "—" : claim.capacity)
                DetailRow(label: "Access Modes", value: claim.accessModesDisplay.isEmpty ? "—" : claim.accessModesDisplay)
                DetailRow(label: "Storage Class", value: claim.storageClassName.isEmpty ? "—" : claim.storageClassName)
                DetailRow(label: "Volume", value: claim.volumeName.isEmpty ? "—" : claim.volumeName)
            }
        }

        if let requests = claim.spec?.resources?.requests, !requests.isEmpty {
            DetailSection("Requested") {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(requests.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                        DetailRow(label: key, value: value)
                    }
                }
            }
        }

        if let limits = claim.spec?.resources?.limits, !limits.isEmpty {
            DetailSection("Limits") {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(limits.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                        DetailRow(label: key, value: value)
                    }
                }
            }
        }
    }
}

// MARK: - NetworkPolicy

struct NetworkPolicyDetailContent: View {
    let policy: NetworkPolicy

    var body: some View {
        DetailSection("Info") {
            VStack(alignment: .leading, spacing: 4) {
                DetailRow(label: "Pod Selector", value: policy.podSelectorDisplay)
                DetailRow(label: "Policy Types", value: policy.policyTypesDisplay.isEmpty ? "—" : policy.policyTypesDisplay)
            }
        }

        let ingressRules = policy.spec?.ingress ?? []
        DetailSection("Ingress Rules (\(ingressRules.count))") {
            if ingressRules.isEmpty {
                Text("None")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(ingressRules.enumerated()), id: \.offset) { _, rule in
                        ruleCard(direction: "From", peers: rule.from, ports: rule.ports)
                    }
                }
            }
        }

        let egressRules = policy.spec?.egress ?? []
        DetailSection("Egress Rules (\(egressRules.count))") {
            if egressRules.isEmpty {
                Text("None")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(egressRules.enumerated()), id: \.offset) { _, rule in
                        ruleCard(direction: "To", peers: rule.to, ports: rule.ports)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func ruleCard(direction: String, peers: [NetworkPolicyPeer]?, ports: [NetworkPolicyPort]?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            let peerList = peers ?? []
            if peerList.isEmpty {
                DetailRow(label: direction, value: "(anywhere)")
            } else {
                ForEach(Array(peerList.enumerated()), id: \.offset) { _, peer in
                    DetailRow(label: direction, value: peerDescription(peer))
                }
            }
            let portList = ports ?? []
            DetailRow(label: "Ports", value: portList.isEmpty ? "(all)" : portList.map { portDescription($0) }.joined(separator: ", "))
        }
        .padding(8)
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func peerDescription(_ peer: NetworkPolicyPeer) -> String {
        var parts: [String] = []
        if let pods = peer.podSelector?.matchLabels, !pods.isEmpty {
            parts.append("pods[\(labelList(pods))]")
        }
        if let namespaces = peer.namespaceSelector?.matchLabels, !namespaces.isEmpty {
            parts.append("namespaces[\(labelList(namespaces))]")
        }
        return parts.isEmpty ? "(any)" : parts.joined(separator: " ")
    }

    private func labelList(_ labels: [String: String]) -> String {
        labels.sorted(by: { $0.key < $1.key }).map { "\($0.key)=\($0.value)" }.joined(separator: ",")
    }

    private func portDescription(_ port: NetworkPolicyPort) -> String {
        "\(port.port?.displayValue ?? "any")/\(port.protocol ?? "TCP")"
    }
}

// MARK: - ServiceAccount

struct ServiceAccountDetailContent: View {
    let serviceAccount: ServiceAccount

    var body: some View {
        let secrets = serviceAccount.secrets ?? []
        DetailSection("Secrets (\(secrets.count))") {
            if secrets.isEmpty {
                Text("None")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(secrets.enumerated()), id: \.offset) { _, secret in
                        Text(secret.name ?? "(unnamed)")
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            }
        }

        // Cloud IAM bindings (IRSA, Workload Identity) are annotations, so they belong on screen here.
        DetailSection("Annotations") {
            if annotations.isEmpty {
                Text("None")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(annotations, id: \.key) { key, value in
                        DetailRow(label: key, value: value)
                    }
                }
            }
        }
    }

    private var annotations: [(key: String, value: String)] {
        // last-applied-configuration is an entire embedded manifest — the YAML tab is the place for it.
        (serviceAccount.metadata.annotations ?? [:])
            .filter { $0.key != "kubectl.kubernetes.io/last-applied-configuration" }
            .sorted { $0.key < $1.key }
    }
}

// MARK: - HorizontalPodAutoscaler

struct HorizontalPodAutoscalerDetailContent: View {
    let autoscaler: HorizontalPodAutoscaler

    var body: some View {
        DetailSection("Scale Target") {
            VStack(alignment: .leading, spacing: 4) {
                if let target = autoscaler.spec?.scaleTargetRef {
                    DetailRow(label: "Kind", value: target.kind ?? "—")
                    DetailRow(label: "Name", value: target.name ?? "—")
                } else {
                    DetailRow(label: "Target", value: "—")
                }
            }
        }

        DetailSection("Replicas") {
            VStack(alignment: .leading, spacing: 4) {
                DetailRow(label: "Min", value: "\(autoscaler.minReplicas)")
                DetailRow(label: "Max", value: "\(autoscaler.maxReplicas)")
                DetailRow(label: "Current", value: "\(autoscaler.currentReplicas)")
                DetailRow(label: "Desired", value: "\(autoscaler.desiredReplicas)")
            }
        }

        DetailSection("Metrics") {
            VStack(alignment: .leading, spacing: 4) {
                let targets = autoscaler.spec?.metrics ?? []
                let current = autoscaler.status?.currentMetrics ?? []
                if targets.isEmpty && current.isEmpty {
                    Text("None")
                        .foregroundStyle(.secondary)
                } else {
                    if !targets.isEmpty {
                        Text("Targets")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fontWeight(.semibold)
                        ForEach(Array(targets.enumerated()), id: \.offset) { _, metric in
                            DetailRow(
                                label: metric.resource?.name ?? metric.type ?? "metric",
                                value: targetDisplay(metric.resource?.target)
                            )
                        }
                    }
                    if !current.isEmpty {
                        Text("Current")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fontWeight(.semibold)
                            .padding(.top, 4)
                        ForEach(Array(current.enumerated()), id: \.offset) { _, metric in
                            DetailRow(
                                label: metric.resource?.name ?? metric.type ?? "metric",
                                value: currentDisplay(metric.resource?.current)
                            )
                        }
                    }
                }
            }
        }
    }

    private func targetDisplay(_ target: HPAMetricTarget?) -> String {
        if let utilization = target?.averageUtilization { return "\(utilization)%" }
        if let value = target?.averageValue { return value }
        return "—"
    }

    private func currentDisplay(_ value: HPAMetricValueStatus?) -> String {
        if let utilization = value?.averageUtilization { return "\(utilization)%" }
        if let average = value?.averageValue { return average }
        return "—"
    }
}

// MARK: - Namespace

struct NamespaceDetailContent: View {
    let namespace: Namespace

    var body: some View {
        DetailSection("Status") {
            DetailRow(label: "Phase", value: namespace.phase)
        }

        DetailSection("Labels") {
            if let labels = namespace.metadata.labels, !labels.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(labels.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                        DetailRow(label: key, value: value)
                    }
                }
            } else {
                Text("None")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Endpoints

struct EndpointsDetailContent: View {
    let endpoints: Endpoints

    var body: some View {
        let subsets = endpoints.subsets ?? []
        DetailSection("Subsets (\(subsets.count))") {
            if subsets.isEmpty {
                Text("None")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(subsets.enumerated()), id: \.offset) { index, subset in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Subset \(index + 1)")
                                .fontWeight(.medium)

                            let addresses = subset.addresses ?? []
                            if addresses.isEmpty {
                                DetailRow(label: "Ready", value: "None")
                            } else {
                                ForEach(Array(addresses.enumerated()), id: \.offset) { _, address in
                                    DetailRow(label: "Ready", value: addressDisplay(address))
                                }
                            }

                            let notReady = subset.notReadyAddresses ?? []
                            ForEach(Array(notReady.enumerated()), id: \.offset) { _, address in
                                DetailRow(label: "Not Ready", value: addressDisplay(address))
                            }

                            let ports = subset.ports ?? []
                            DetailRow(
                                label: "Ports",
                                value: ports.isEmpty ? "None" : ports.map { portDisplay($0) }.joined(separator: ", ")
                            )
                        }
                        .padding(8)
                        .background(.quaternary.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
        }
    }

    private func addressDisplay(_ address: EndpointAddress) -> String {
        var text = address.ip ?? address.hostname ?? "—"
        if let node = address.nodeName { text += " on \(node)" }
        return text
    }

    private func portDisplay(_ port: EndpointPort) -> String {
        let name = port.name.map { "\($0):" } ?? ""
        return "\(name)\(port.port)/\(port.protocol ?? "TCP")"
    }
}

// MARK: - RBAC

struct PolicyRulesSection: View {
    let rules: [PolicyRule]?

    var body: some View {
        let items = rules ?? []
        DetailSection("Rules (\(items.count))") {
            if items.isEmpty {
                Text("None")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, rule in
                        VStack(alignment: .leading, spacing: 4) {
                            DetailRow(label: "API Groups", value: joinedValues(rule.apiGroups))
                            DetailRow(label: "Resources", value: joinedValues(rule.resources))
                            DetailRow(label: "Verbs", value: joinedValues(rule.verbs))
                            if let names = rule.resourceNames, !names.isEmpty {
                                DetailRow(label: "Resource Names", value: joinedValues(names))
                            }
                            if let urls = rule.nonResourceURLs, !urls.isEmpty {
                                DetailRow(label: "Non-Resource URLs", value: joinedValues(urls))
                            }
                        }
                        .padding(8)
                        .background(.quaternary.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
        }
    }

    /// The core API group is the empty string on the wire, which reads as a gap.
    private func joinedValues(_ values: [String]?) -> String {
        guard let values, !values.isEmpty else { return "—" }
        return values.map { $0.isEmpty ? "(core)" : $0 }.joined(separator: ", ")
    }
}

struct RBACBindingContent: View {
    let roleRef: RoleRef?
    let subjects: [RBACSubject]?

    var body: some View {
        DetailSection("Role Reference") {
            VStack(alignment: .leading, spacing: 4) {
                DetailRow(label: "Kind", value: roleRef?.kind ?? "—")
                DetailRow(label: "Name", value: roleRef?.name ?? "—")
                if let group = roleRef?.apiGroup, !group.isEmpty {
                    DetailRow(label: "API Group", value: group)
                }
            }
        }

        let items = subjects ?? []
        DetailSection("Subjects (\(items.count))") {
            if items.isEmpty {
                Text("None")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, subject in
                        DetailRow(label: subject.kind ?? "Subject", value: subjectDisplay(subject))
                    }
                }
            }
        }
    }

    private func subjectDisplay(_ subject: RBACSubject) -> String {
        let name = subject.name ?? "—"
        if let namespace = subject.namespace, !namespace.isEmpty {
            return "\(namespace)/\(name)"
        }
        return name
    }
}

struct RoleDetailContent: View {
    let role: Role

    var body: some View {
        DetailSection("Info") {
            DetailRow(label: "Verbs", value: role.verbsSummary.isEmpty ? "—" : role.verbsSummary)
        }

        PolicyRulesSection(rules: role.rules)
    }
}

struct ClusterRoleDetailContent: View {
    let clusterRole: ClusterRole

    var body: some View {
        DetailSection("Info") {
            DetailRow(label: "Verbs", value: clusterRole.verbsSummary.isEmpty ? "—" : clusterRole.verbsSummary)
        }

        PolicyRulesSection(rules: clusterRole.rules)
    }
}

struct RoleBindingDetailContent: View {
    let roleBinding: RoleBinding

    var body: some View {
        RBACBindingContent(roleRef: roleBinding.roleRef, subjects: roleBinding.subjects)
    }
}

struct ClusterRoleBindingDetailContent: View {
    let clusterRoleBinding: ClusterRoleBinding

    var body: some View {
        RBACBindingContent(roleRef: clusterRoleBinding.roleRef, subjects: clusterRoleBinding.subjects)
    }
}

// MARK: - StorageClass

struct StorageClassDetailContent: View {
    let storageClass: StorageClass

    var body: some View {
        DetailSection("Info") {
            VStack(alignment: .leading, spacing: 4) {
                DetailRow(label: "Provisioner", value: storageClass.provisioner ?? "—")
                DetailRow(label: "Reclaim Policy", value: storageClass.reclaimPolicyDisplay)
                DetailRow(label: "Binding Mode", value: storageClass.bindingModeDisplay)
                DetailRow(label: "Volume Expansion", value: (storageClass.allowVolumeExpansion ?? false) ? "Allowed" : "Not allowed")
                DetailRow(label: "Default Class", value: storageClass.isDefault ? "Yes" : "No")
            }
        }
    }
}

// MARK: - ResourceQuota

struct ResourceQuotaDetailContent: View {
    let resourceQuota: ResourceQuota

    private struct QuotaRow: Identifiable {
        let id: String
        let used: String
        let hard: String
    }

    var body: some View {
        DetailSection("Quota") {
            if rows.isEmpty {
                Text("No quota defined")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Resource")
                            .frame(width: 220, alignment: .leading)
                        Text("Used")
                            .frame(width: 90, alignment: .trailing)
                        Text("Hard")
                            .frame(width: 90, alignment: .trailing)
                        Spacer()
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    ForEach(rows) { row in
                        HStack {
                            Text(row.id)
                                .frame(width: 220, alignment: .leading)
                            Text(row.used)
                                .frame(width: 90, alignment: .trailing)
                            Text(row.hard)
                                .frame(width: 90, alignment: .trailing)
                            Spacer()
                        }
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                    }
                }
            }
        }
    }

    private var rows: [QuotaRow] {
        let hard = resourceQuota.status?.hard ?? resourceQuota.spec?.hard ?? [:]
        let used = resourceQuota.status?.used ?? [:]
        return Set(hard.keys).union(used.keys).sorted().map {
            QuotaRow(id: $0, used: used[$0] ?? "—", hard: hard[$0] ?? "—")
        }
    }
}

// MARK: - PodDisruptionBudget

struct PodDisruptionBudgetDetailContent: View {
    let budget: PodDisruptionBudget

    var body: some View {
        DetailSection("Budget") {
            VStack(alignment: .leading, spacing: 4) {
                DetailRow(label: "Min Available", value: budget.minAvailableDisplay)
                DetailRow(label: "Max Unavailable", value: budget.maxUnavailableDisplay)
            }
        }

        DetailSection("Status") {
            VStack(alignment: .leading, spacing: 4) {
                DetailRow(label: "Healthy", value: budget.healthyDisplay)
                DetailRow(label: "Disruptions Allowed", value: "\(budget.allowedDisruptions)")
                if let expected = budget.status?.expectedPods {
                    DetailRow(label: "Expected Pods", value: "\(expected)")
                }
            }
        }
    }
}

// MARK: - LimitRange

struct LimitRangeDetailContent: View {
    let limitRange: LimitRange

    var body: some View {
        let limits = limitRange.spec?.limits ?? []
        if limits.isEmpty {
            Text("No limits")
                .foregroundStyle(.secondary)
        } else {
            ForEach(Array(limits.enumerated()), id: \.offset) { _, item in
                DetailSection(item.type ?? "Limit") {
                    VStack(alignment: .leading, spacing: 4) {
                        constraintGroup("Min", values: item.min)
                        constraintGroup("Max", values: item.max)
                        constraintGroup("Default", values: item.default)
                        constraintGroup("Default Request", values: item.defaultRequest)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func constraintGroup(_ title: String, values: [String: String]?) -> some View {
        if let values, !values.isEmpty {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fontWeight(.semibold)
                .padding(.top, 4)
            ForEach(values.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                DetailRow(label: key, value: value)
            }
        }
    }
}

// MARK: - PriorityClass

struct PriorityClassDetailContent: View {
    let priorityClass: PriorityClass

    var body: some View {
        DetailSection("Info") {
            VStack(alignment: .leading, spacing: 4) {
                DetailRow(label: "Value", value: priorityClass.valueDisplay)
                DetailRow(label: "Global Default", value: priorityClass.isGlobalDefault ? "Yes" : "No")
                DetailRow(label: "Preemption Policy", value: priorityClass.preemptionPolicy ?? "PreemptLowerPriority")
            }
        }

        if let description = priorityClass.description, !description.isEmpty {
            DetailSection("Description") {
                Text(description)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - Lease

struct LeaseDetailContent: View {
    let lease: Lease

    var body: some View {
        DetailSection("Holder") {
            VStack(alignment: .leading, spacing: 4) {
                DetailRow(label: "Holder Identity", value: lease.holder)
                DetailRow(label: "Lease Duration", value: lease.durationDisplay)
                DetailRow(label: "Renew Time", value: lease.renewTime.isEmpty ? "—" : lease.renewTime)
                if let acquired = lease.spec?.acquireTime, !acquired.isEmpty {
                    DetailRow(label: "Acquire Time", value: acquired)
                }
            }
        }
    }
}

// MARK: - Admission Webhooks

struct AdmissionWebhookSection: View {
    let webhooks: [AdmissionWebhook]?

    var body: some View {
        let hooks = webhooks ?? []
        DetailSection("Webhooks (\(hooks.count))") {
            if hooks.isEmpty {
                Text("None")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(hooks.enumerated()), id: \.offset) { _, hook in
                        Text(hook.name ?? "(unnamed)")
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }
}

struct MutatingWebhookConfigurationDetailContent: View {
    let configuration: MutatingWebhookConfiguration

    var body: some View {
        AdmissionWebhookSection(webhooks: configuration.webhooks)
    }
}

struct ValidatingWebhookConfigurationDetailContent: View {
    let configuration: ValidatingWebhookConfiguration

    var body: some View {
        AdmissionWebhookSection(webhooks: configuration.webhooks)
    }
}
