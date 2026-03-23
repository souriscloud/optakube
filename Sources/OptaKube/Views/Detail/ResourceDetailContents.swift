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
