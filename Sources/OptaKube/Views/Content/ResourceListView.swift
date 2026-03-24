import SwiftUI

struct ResourceListView: View {
    @Environment(AppViewModel.self) private var viewModel
    @Binding var selectedResource: ResourceIdentifier?

    var body: some View {
        Group {
            if let crd = viewModel.selectedCRD {
                // CRD custom resource view
                crdResourceView(crd: crd)
            } else if viewModel.isLoading && allItems.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Loading \(viewModel.selectedResourceType.displayName)...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let ns = viewModel.selectedNamespace {
                        Text("Namespace: \(ns)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if allItems.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: viewModel.selectedResourceType.systemImage)
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("No \(viewModel.selectedResourceType.displayName)")
                        .font(.title3)
                        .fontWeight(.medium)
                    if let ns = viewModel.selectedNamespace {
                        Text("No resources found in namespace \"\(ns)\"")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button("Show All Namespaces") {
                            viewModel.selectedNamespace = nil
                            Task { await viewModel.refresh() }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    } else {
                        Text("No resources found across all namespaces")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                switch viewModel.selectedResourceType {
                case .pods: podTable
                case .deployments: deploymentTable
                case .services: serviceTable
                case .nodes: nodeTable
                case .statefulSets: statefulSetTable
                case .daemonSets: daemonSetTable
                case .replicaSets: replicaSetTable
                case .jobs: jobTable
                case .cronJobs: cronJobTable
                case .configMaps: configMapTable
                case .secrets: secretTable
                case .ingresses: ingressTable
                case .ingressClasses: ingressClassTable
                case .persistentVolumes: persistentVolumeTable
                case .persistentVolumeClaims: persistentVolumeClaimTable
                case .networkPolicies: networkPolicyTable
                case .serviceAccounts: serviceAccountTable
                case .horizontalPodAutoscalers: hpaTable
                case .namespaces: namespaceTable
                case .endpoints: endpointsTable
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle(viewModel.selectedCRD?.displayName ?? viewModel.selectedResourceType.displayName)
        .safeAreaInset(edge: .top) {
            if !allItems.isEmpty || viewModel.isLoading {
                HStack(spacing: 8) {
                    Circle()
                        .fill(.green)
                        .frame(width: 7, height: 7)
                    Text("\(allItems.count) \(allItems.count == 1 ? "resource" : "resources")")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let ns = viewModel.selectedNamespace {
                        Text(ns)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .foregroundStyle(Color.accentColor)
                    } else {
                        Text("All Namespaces")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if viewModel.isLoading {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 4)
                .background(.bar)
            }
        }
    }

    // MARK: - Pod Table

    private var podTable: some View {
        Table(filteredRows(from: \.pods, type: .pods) { PodRow(id: $0, pod: $1, clusterId: $2) }, selection: $selectedResource) {
            TableColumn("") { item in ResourceStatusBadge(status: item.pod.resourceStatus) }.width(24)
            TableColumn("Name") { item in
                Text(item.pod.name).fontWeight(.medium).foregroundStyle(Color(red: 0.29, green: 0.62, blue: 1.0))
                    .contextMenu { ResourceContextMenu(resource: item.id) }
            }.width(min: 150, ideal: 250)
            TableColumn("Namespace", value: \.pod.namespace).width(min: 80, ideal: 120)
            TableColumn("Ready") { item in Text("\(item.pod.readyCount)/\(item.pod.totalContainers)").monospacedDigit() }.width(50)
            TableColumn("CPU") { item in
                MiniUsageBar(
                    value: podCPU(item.pod.name, ns: item.pod.namespace, clusterId: item.clusterId),
                    label: podCPULabel(item.pod.name, ns: item.pod.namespace, clusterId: item.clusterId),
                    color: .blue
                )
            }.width(80)
            TableColumn("Memory") { item in
                MiniUsageBar(
                    value: podMemory(item.pod.name, ns: item.pod.namespace, clusterId: item.clusterId),
                    label: podMemoryLabel(item.pod.name, ns: item.pod.namespace, clusterId: item.clusterId),
                    color: .purple
                )
            }.width(80)
            TableColumn("Restarts") { item in
                Text("\(item.pod.restartCount)").monospacedDigit()
                    .foregroundStyle(item.pod.restartCount > 0 ? .orange : .primary)
            }.width(55)
            TableColumn("Age") { item in Text(item.pod.age).foregroundStyle(.secondary) }.width(50)
            TableColumn("Node", value: \.pod.nodeName).width(min: 80, ideal: 120)
        }
    }

    // MARK: - Deployment Table

    private var deploymentTable: some View {
        Table(filteredRows(from: \.deployments, type: .deployments) { DeploymentRow(id: $0, deployment: $1, clusterId: $2) }, selection: $selectedResource) {
            TableColumn("") { item in ResourceStatusBadge(status: item.deployment.resourceStatus) }.width(24)
            TableColumn("Name") { item in Text(item.deployment.name).fontWeight(.medium).foregroundStyle(Color(red: 0.29, green: 0.62, blue: 1.0)).contextMenu { ResourceContextMenu(resource: item.id) } }.width(min: 150, ideal: 250)
            TableColumn("Namespace", value: \.deployment.namespace).width(min: 80, ideal: 120)
            TableColumn("Ready") { item in Text("\(item.deployment.readyReplicas)/\(item.deployment.replicas)").monospacedDigit() }.width(60)
            TableColumn("Up-to-date") { item in Text("\(item.deployment.updatedReplicas)").monospacedDigit() }.width(70)
            TableColumn("Available") { item in Text("\(item.deployment.availableReplicas)").monospacedDigit() }.width(65)
            TableColumn("Age") { item in Text(item.deployment.age).foregroundStyle(.secondary) }.width(50)
        }
    }

    // MARK: - Service Table

    private var serviceTable: some View {
        Table(filteredRows(from: \.services, type: .services) { ServiceRow(id: $0, service: $1, clusterId: $2) }, selection: $selectedResource) {
            TableColumn("") { item in ResourceStatusBadge(status: item.service.resourceStatus) }.width(24)
            TableColumn("Name") { item in Text(item.service.name).fontWeight(.medium).foregroundStyle(Color(red: 0.29, green: 0.62, blue: 1.0)).contextMenu { ResourceContextMenu(resource: item.id) } }.width(min: 150, ideal: 250)
            TableColumn("Namespace", value: \.service.namespace).width(min: 80, ideal: 120)
            TableColumn("Type", value: \.service.serviceType).width(80)
            TableColumn("Cluster IP", value: \.service.clusterIP).width(min: 100, ideal: 130)
            TableColumn("Ports") { item in Text(item.service.portsDisplay).font(.caption) }.width(min: 100, ideal: 200)
            TableColumn("Age") { item in Text(item.service.age).foregroundStyle(.secondary) }.width(50)
        }
    }

    // MARK: - Node Table

    private var nodeTable: some View {
        Table(filteredRows(from: \.nodes, type: .nodes, namespaced: false) { NodeRow(id: $0, node: $1, clusterId: $2) }, selection: $selectedResource) {
            TableColumn("") { item in ResourceStatusBadge(status: item.node.resourceStatus) }.width(24)
            TableColumn("Name") { item in Text(item.node.name).fontWeight(.medium).foregroundStyle(Color(red: 0.29, green: 0.62, blue: 1.0)).contextMenu { ResourceContextMenu(resource: item.id) } }.width(min: 150, ideal: 250)
            TableColumn("Roles") { item in Text(item.node.roles) }.width(min: 80, ideal: 100)
            TableColumn("CPU") { item in
                MiniUsageBar(
                    value: nodeCPUPercent(item.node, clusterId: item.clusterId),
                    label: nodeCPULabel(item.node, clusterId: item.clusterId),
                    color: .blue
                )
            }.width(90)
            TableColumn("Memory") { item in
                MiniUsageBar(
                    value: nodeMemPercent(item.node, clusterId: item.clusterId),
                    label: nodeMemLabel(item.node, clusterId: item.clusterId),
                    color: .purple
                )
            }.width(90)
            TableColumn("Version", value: \.node.kubeletVersion).width(min: 60, ideal: 90)
            TableColumn("Age") { item in Text(item.node.age).foregroundStyle(.secondary) }.width(50)
        }
    }

    // MARK: - StatefulSet Table

    private var statefulSetTable: some View {
        Table(filteredRows(from: \.statefulSets, type: .statefulSets) { StatefulSetRow(id: $0, statefulSet: $1, clusterId: $2) }, selection: $selectedResource) {
            TableColumn("") { item in ResourceStatusBadge(status: item.statefulSet.resourceStatus) }.width(24)
            TableColumn("Name") { item in Text(item.statefulSet.name).fontWeight(.medium).foregroundStyle(Color(red: 0.29, green: 0.62, blue: 1.0)).contextMenu { ResourceContextMenu(resource: item.id) } }.width(min: 150, ideal: 250)
            TableColumn("Namespace", value: \.statefulSet.namespace).width(min: 80, ideal: 120)
            TableColumn("Ready") { item in Text("\(item.statefulSet.readyReplicas)/\(item.statefulSet.replicas)").monospacedDigit() }.width(60)
            TableColumn("Age") { item in Text(item.statefulSet.age).foregroundStyle(.secondary) }.width(50)
        }
    }

    // MARK: - DaemonSet Table

    private var daemonSetTable: some View {
        Table(filteredRows(from: \.daemonSets, type: .daemonSets) { DaemonSetRow(id: $0, daemonSet: $1, clusterId: $2) }, selection: $selectedResource) {
            TableColumn("") { item in ResourceStatusBadge(status: item.daemonSet.resourceStatus) }.width(24)
            TableColumn("Name") { item in Text(item.daemonSet.name).fontWeight(.medium).foregroundStyle(Color(red: 0.29, green: 0.62, blue: 1.0)).contextMenu { ResourceContextMenu(resource: item.id) } }.width(min: 150, ideal: 250)
            TableColumn("Namespace", value: \.daemonSet.namespace).width(min: 80, ideal: 120)
            TableColumn("Desired") { item in Text("\(item.daemonSet.desiredNumberScheduled)").monospacedDigit() }.width(55)
            TableColumn("Ready") { item in Text("\(item.daemonSet.numberReady)").monospacedDigit() }.width(50)
            TableColumn("Age") { item in Text(item.daemonSet.age).foregroundStyle(.secondary) }.width(50)
        }
    }

    // MARK: - ReplicaSet Table

    private var replicaSetTable: some View {
        Table(filteredRows(from: \.replicaSets, type: .replicaSets) { ReplicaSetRow(id: $0, replicaSet: $1, clusterId: $2) }, selection: $selectedResource) {
            TableColumn("") { item in ResourceStatusBadge(status: item.replicaSet.resourceStatus) }.width(24)
            TableColumn("Name") { item in Text(item.replicaSet.name).fontWeight(.medium).foregroundStyle(Color(red: 0.29, green: 0.62, blue: 1.0)).contextMenu { ResourceContextMenu(resource: item.id) } }.width(min: 150, ideal: 250)
            TableColumn("Namespace", value: \.replicaSet.namespace).width(min: 80, ideal: 120)
            TableColumn("Ready") { item in Text("\(item.replicaSet.readyReplicas)/\(item.replicaSet.replicas)").monospacedDigit() }.width(60)
            TableColumn("Age") { item in Text(item.replicaSet.age).foregroundStyle(.secondary) }.width(50)
        }
    }

    // MARK: - Job Table

    private var jobTable: some View {
        Table(filteredRows(from: \.jobs, type: .jobs) { JobRow(id: $0, job: $1, clusterId: $2) }, selection: $selectedResource) {
            TableColumn("") { item in ResourceStatusBadge(status: item.job.resourceStatus) }.width(24)
            TableColumn("Name") { item in Text(item.job.name).fontWeight(.medium).foregroundStyle(Color(red: 0.29, green: 0.62, blue: 1.0)).contextMenu { ResourceContextMenu(resource: item.id) } }.width(min: 150, ideal: 250)
            TableColumn("Namespace", value: \.job.namespace).width(min: 80, ideal: 120)
            TableColumn("Completions") { item in Text("\(item.job.succeeded)/\(item.job.completions)").monospacedDigit() }.width(80)
            TableColumn("Duration") { item in Text(item.job.duration).foregroundStyle(.secondary) }.width(70)
            TableColumn("Age") { item in Text(item.job.age).foregroundStyle(.secondary) }.width(50)
        }
    }

    // MARK: - CronJob Table

    private var cronJobTable: some View {
        Table(filteredRows(from: \.cronJobs, type: .cronJobs) { CronJobRow(id: $0, cronJob: $1, clusterId: $2) }, selection: $selectedResource) {
            TableColumn("") { item in ResourceStatusBadge(status: item.cronJob.resourceStatus) }.width(24)
            TableColumn("Name") { item in Text(item.cronJob.name).fontWeight(.medium).foregroundStyle(Color(red: 0.29, green: 0.62, blue: 1.0)).contextMenu { ResourceContextMenu(resource: item.id) } }.width(min: 150, ideal: 250)
            TableColumn("Namespace", value: \.cronJob.namespace).width(min: 80, ideal: 120)
            TableColumn("Schedule", value: \.cronJob.schedule).width(min: 80, ideal: 120)
            TableColumn("Suspended") { item in
                Image(systemName: item.cronJob.isSuspended ? "pause.circle.fill" : "play.circle.fill")
                    .foregroundStyle(item.cronJob.isSuspended ? .orange : .green)
            }.width(65)
            TableColumn("Last Run") { item in Text(item.cronJob.lastScheduleDisplay).foregroundStyle(.secondary) }.width(80)
            TableColumn("Age") { item in Text(item.cronJob.age).foregroundStyle(.secondary) }.width(50)
        }
    }

    // MARK: - ConfigMap Table

    private var configMapTable: some View {
        Table(filteredRows(from: \.configMaps, type: .configMaps) { ConfigMapRow(id: $0, configMap: $1, clusterId: $2) }, selection: $selectedResource) {
            TableColumn("") { _ in ResourceStatusBadge(status: .running) }.width(24)
            TableColumn("Name") { item in Text(item.configMap.name).fontWeight(.medium).foregroundStyle(Color(red: 0.29, green: 0.62, blue: 1.0)).contextMenu { ResourceContextMenu(resource: item.id) } }.width(min: 150, ideal: 250)
            TableColumn("Namespace", value: \.configMap.namespace).width(min: 80, ideal: 120)
            TableColumn("Data") { item in Text("\(item.configMap.dataCount) keys").monospacedDigit() }.width(70)
            TableColumn("Age") { item in Text(item.configMap.age).foregroundStyle(.secondary) }.width(50)
        }
    }

    // MARK: - Secret Table

    private var secretTable: some View {
        Table(filteredRows(from: \.secrets, type: .secrets) { SecretRow(id: $0, secret: $1, clusterId: $2) }, selection: $selectedResource) {
            TableColumn("") { _ in ResourceStatusBadge(status: .running) }.width(24)
            TableColumn("Name") { item in Text(item.secret.name).fontWeight(.medium).foregroundStyle(Color(red: 0.29, green: 0.62, blue: 1.0)).contextMenu { ResourceContextMenu(resource: item.id) } }.width(min: 150, ideal: 250)
            TableColumn("Namespace", value: \.secret.namespace).width(min: 80, ideal: 120)
            TableColumn("Type", value: \.secret.secretType).width(min: 100, ideal: 150)
            TableColumn("Data") { item in Text("\(item.secret.dataCount) keys").monospacedDigit() }.width(70)
            TableColumn("Age") { item in Text(item.secret.age).foregroundStyle(.secondary) }.width(50)
        }
    }

    // MARK: - Ingress Table

    private var ingressTable: some View {
        Table(filteredRows(from: \.ingresses, type: .ingresses) { IngressRow(id: $0, ingress: $1, clusterId: $2) }, selection: $selectedResource) {
            TableColumn("") { item in ResourceStatusBadge(status: item.ingress.resourceStatus) }.width(24)
            TableColumn("Name") { item in Text(item.ingress.name).fontWeight(.medium).foregroundStyle(Color(red: 0.29, green: 0.62, blue: 1.0)).contextMenu { ResourceContextMenu(resource: item.id) } }.width(min: 150, ideal: 250)
            TableColumn("Namespace", value: \.ingress.namespace).width(min: 80, ideal: 120)
            TableColumn("Hosts") { item in Text(item.ingress.hostsDisplay).font(.caption) }.width(min: 100, ideal: 200)
            TableColumn("Paths") { item in Text(item.ingress.pathsDisplay).font(.caption) }.width(min: 80, ideal: 150)
            TableColumn("Backend") { item in Text(item.ingress.backendServiceDisplay).font(.caption) }.width(min: 80, ideal: 150)
            TableColumn("TLS") { item in
                Image(systemName: item.ingress.tlsEnabled ? "lock.fill" : "lock.open")
                    .foregroundStyle(item.ingress.tlsEnabled ? .green : .secondary)
            }.width(35)
            TableColumn("Age") { item in Text(item.ingress.age).foregroundStyle(.secondary) }.width(50)
        }
    }

    // MARK: - IngressClass Table

    private var ingressClassTable: some View {
        Table(filteredRows(from: \.ingressClasses, type: .ingressClasses, namespaced: false) { IngressClassRow(id: $0, ingressClass: $1, clusterId: $2) }, selection: $selectedResource) {
            TableColumn("") { item in ResourceStatusBadge(status: item.ingressClass.resourceStatus) }.width(24)
            TableColumn("Name") { item in Text(item.ingressClass.name).fontWeight(.medium).foregroundStyle(Color(red: 0.29, green: 0.62, blue: 1.0)).contextMenu { ResourceContextMenu(resource: item.id) } }.width(min: 150, ideal: 250)
            TableColumn("Controller", value: \.ingressClass.controller).width(min: 150, ideal: 250)
            TableColumn("Default") { item in
                Image(systemName: item.ingressClass.isDefault ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.ingressClass.isDefault ? .green : .secondary)
            }.width(55)
            TableColumn("Age") { item in Text(item.ingressClass.age).foregroundStyle(.secondary) }.width(50)
        }
    }

    // MARK: - PersistentVolume Table

    private var persistentVolumeTable: some View {
        Table(filteredRows(from: \.persistentVolumes, type: .persistentVolumes, namespaced: false) { PersistentVolumeRow(id: $0, persistentVolume: $1, clusterId: $2) }, selection: $selectedResource) {
            TableColumn("") { item in ResourceStatusBadge(status: item.persistentVolume.resourceStatus) }.width(24)
            TableColumn("Name") { item in Text(item.persistentVolume.name).fontWeight(.medium).foregroundStyle(Color(red: 0.29, green: 0.62, blue: 1.0)).contextMenu { ResourceContextMenu(resource: item.id) } }.width(min: 150, ideal: 250)
            TableColumn("Capacity", value: \.persistentVolume.capacity).width(70)
            TableColumn("Access Modes") { item in Text(item.persistentVolume.accessModesDisplay).font(.caption) }.width(min: 80, ideal: 150)
            TableColumn("Reclaim Policy", value: \.persistentVolume.reclaimPolicy).width(100)
            TableColumn("Status", value: \.persistentVolume.phase).width(70)
            TableColumn("Storage Class", value: \.persistentVolume.storageClassName).width(min: 80, ideal: 120)
            TableColumn("Age") { item in Text(item.persistentVolume.age).foregroundStyle(.secondary) }.width(50)
        }
    }

    // MARK: - PersistentVolumeClaim Table

    private var persistentVolumeClaimTable: some View {
        Table(filteredRows(from: \.persistentVolumeClaims, type: .persistentVolumeClaims) { PersistentVolumeClaimRow(id: $0, persistentVolumeClaim: $1, clusterId: $2) }, selection: $selectedResource) {
            TableColumn("") { item in ResourceStatusBadge(status: item.persistentVolumeClaim.resourceStatus) }.width(24)
            TableColumn("Name") { item in Text(item.persistentVolumeClaim.name).fontWeight(.medium).foregroundStyle(Color(red: 0.29, green: 0.62, blue: 1.0)).contextMenu { ResourceContextMenu(resource: item.id) } }.width(min: 150, ideal: 250)
            TableColumn("Namespace", value: \.persistentVolumeClaim.namespace).width(min: 80, ideal: 120)
            TableColumn("Status", value: \.persistentVolumeClaim.phase).width(70)
            TableColumn("Volume", value: \.persistentVolumeClaim.volumeName).width(min: 80, ideal: 150)
            TableColumn("Capacity", value: \.persistentVolumeClaim.capacity).width(70)
            TableColumn("Access Modes") { item in Text(item.persistentVolumeClaim.accessModesDisplay).font(.caption) }.width(min: 80, ideal: 120)
            TableColumn("Storage Class", value: \.persistentVolumeClaim.storageClassName).width(min: 80, ideal: 120)
            TableColumn("Age") { item in Text(item.persistentVolumeClaim.age).foregroundStyle(.secondary) }.width(50)
        }
    }

    // MARK: - NetworkPolicy Table

    private var networkPolicyTable: some View {
        Table(filteredRows(from: \.networkPolicies, type: .networkPolicies) { NetworkPolicyRow(id: $0, networkPolicy: $1, clusterId: $2) }, selection: $selectedResource) {
            TableColumn("") { item in ResourceStatusBadge(status: item.networkPolicy.resourceStatus) }.width(24)
            TableColumn("Name") { item in Text(item.networkPolicy.name).fontWeight(.medium).foregroundStyle(Color(red: 0.29, green: 0.62, blue: 1.0)).contextMenu { ResourceContextMenu(resource: item.id) } }.width(min: 150, ideal: 250)
            TableColumn("Namespace", value: \.networkPolicy.namespace).width(min: 80, ideal: 120)
            TableColumn("Pod Selector") { item in Text(item.networkPolicy.podSelectorDisplay).font(.caption) }.width(min: 100, ideal: 200)
            TableColumn("Policy Types") { item in Text(item.networkPolicy.policyTypesDisplay) }.width(min: 80, ideal: 120)
            TableColumn("Age") { item in Text(item.networkPolicy.age).foregroundStyle(.secondary) }.width(50)
        }
    }

    // MARK: - ServiceAccount Table

    private var serviceAccountTable: some View {
        Table(filteredRows(from: \.serviceAccounts, type: .serviceAccounts) { ServiceAccountRow(id: $0, serviceAccount: $1, clusterId: $2) }, selection: $selectedResource) {
            TableColumn("") { _ in ResourceStatusBadge(status: .running) }.width(24)
            TableColumn("Name") { item in Text(item.serviceAccount.name).fontWeight(.medium).foregroundStyle(Color(red: 0.29, green: 0.62, blue: 1.0)).contextMenu { ResourceContextMenu(resource: item.id) } }.width(min: 150, ideal: 250)
            TableColumn("Namespace", value: \.serviceAccount.namespace).width(min: 80, ideal: 120)
            TableColumn("Secrets") { item in Text("\(item.serviceAccount.secretsCount)").monospacedDigit() }.width(55)
            TableColumn("Age") { item in Text(item.serviceAccount.age).foregroundStyle(.secondary) }.width(50)
        }
    }

    // MARK: - HorizontalPodAutoscaler Table

    private var hpaTable: some View {
        Table(filteredRows(from: \.horizontalPodAutoscalers, type: .horizontalPodAutoscalers) { HPARow(id: $0, hpa: $1, clusterId: $2) }, selection: $selectedResource) {
            TableColumn("") { item in ResourceStatusBadge(status: item.hpa.resourceStatus) }.width(24)
            TableColumn("Name") { item in Text(item.hpa.name).fontWeight(.medium).foregroundStyle(Color(red: 0.29, green: 0.62, blue: 1.0)).contextMenu { ResourceContextMenu(resource: item.id) } }.width(min: 150, ideal: 250)
            TableColumn("Namespace", value: \.hpa.namespace).width(min: 80, ideal: 120)
            TableColumn("Min") { item in Text("\(item.hpa.minReplicas)").monospacedDigit() }.width(35)
            TableColumn("Max") { item in Text("\(item.hpa.maxReplicas)").monospacedDigit() }.width(35)
            TableColumn("Replicas") { item in Text("\(item.hpa.currentReplicas)/\(item.hpa.desiredReplicas)").monospacedDigit() }.width(65)
            TableColumn("Current") { item in Text(item.hpa.currentMetricsDisplay).font(.caption) }.width(min: 80, ideal: 150)
            TableColumn("Target") { item in Text(item.hpa.targetMetricsDisplay).font(.caption) }.width(min: 80, ideal: 150)
            TableColumn("Age") { item in Text(item.hpa.age).foregroundStyle(.secondary) }.width(50)
        }
    }

    // MARK: - Namespace Table

    private var namespaceTable: some View {
        Table(filteredRows(from: \.namespaces, type: .namespaces, namespaced: false) { NamespaceRow(id: $0, ns: $1, clusterId: $2) }, selection: $selectedResource) {
            TableColumn("") { item in ResourceStatusBadge(status: item.ns.resourceStatus) }.width(24)
            TableColumn("Name") { item in Text(item.ns.name).fontWeight(.medium).foregroundStyle(Color(red: 0.29, green: 0.62, blue: 1.0)).contextMenu { ResourceContextMenu(resource: item.id) } }.width(min: 150, ideal: 250)
            TableColumn("Status", value: \.ns.phase).width(80)
            TableColumn("Age") { item in Text(item.ns.age).foregroundStyle(.secondary) }.width(50)
        }
    }

    // MARK: - Endpoints Table

    private var endpointsTable: some View {
        Table(filteredRows(from: \.endpoints, type: .endpoints) { EndpointsRow(id: $0, endpoints: $1, clusterId: $2) }, selection: $selectedResource) {
            TableColumn("") { item in ResourceStatusBadge(status: item.endpoints.resourceStatus) }.width(24)
            TableColumn("Name") { item in Text(item.endpoints.name).fontWeight(.medium).foregroundStyle(Color(red: 0.29, green: 0.62, blue: 1.0)).contextMenu { ResourceContextMenu(resource: item.id) } }.width(min: 150, ideal: 250)
            TableColumn("Namespace", value: \.endpoints.namespace).width(min: 80, ideal: 120)
            TableColumn("Addresses") { item in Text("\(item.endpoints.addressCount)").monospacedDigit() }.width(65)
            TableColumn("Ports") { item in Text(item.endpoints.portsDisplay).font(.caption) }.width(min: 100, ideal: 200)
            TableColumn("Age") { item in Text(item.endpoints.age).foregroundStyle(.secondary) }.width(50)
        }
    }

    // MARK: - Generic Row Builder

    private func filteredRows<T: K8sResource, Row: Identifiable>(
        from keyPath: KeyPath<AppViewModel, [String: [T]]>,
        type: ResourceType,
        namespaced: Bool = true,
        build: (ResourceIdentifier, T, String) -> Row
    ) -> [Row] where Row.ID == ResourceIdentifier {
        var rows: [Row] = []
        for clusterId in viewModel.selectedClusterIds {
            for item in viewModel[keyPath: keyPath][clusterId] ?? [] {
                let rid = ResourceIdentifier(
                    clusterId: clusterId,
                    resourceType: type,
                    name: item.name,
                    namespace: namespaced ? item.metadata.namespace : nil
                )
                rows.append(build(rid, item, clusterId))
            }
        }
        if !viewModel.searchText.isEmpty {
            rows = rows.filter { row in
                if let rid = (row as? any ResourceRow)?.resourceId {
                    return rid.name.localizedCaseInsensitiveContains(viewModel.searchText)
                }
                return true
            }
        }
        return rows
    }

    private var allItems: [ResourceIdentifier] {
        var items: [ResourceIdentifier] = []
        for clusterId in viewModel.selectedClusterIds {
            let type = viewModel.selectedResourceType
            func add<T: K8sResource>(_ kp: KeyPath<AppViewModel, [String: [T]]>, namespaced: Bool = true) {
                items += (viewModel[keyPath: kp][clusterId] ?? []).map {
                    ResourceIdentifier(clusterId: clusterId, resourceType: type, name: $0.name, namespace: namespaced ? $0.metadata.namespace : nil)
                }
            }
            switch type {
            case .pods: add(\.pods)
            case .deployments: add(\.deployments)
            case .services: add(\.services)
            case .nodes: add(\.nodes, namespaced: false)
            case .statefulSets: add(\.statefulSets)
            case .daemonSets: add(\.daemonSets)
            case .replicaSets: add(\.replicaSets)
            case .jobs: add(\.jobs)
            case .cronJobs: add(\.cronJobs)
            case .configMaps: add(\.configMaps)
            case .secrets: add(\.secrets)
            case .ingresses: add(\.ingresses)
            case .ingressClasses: add(\.ingressClasses, namespaced: false)
            case .persistentVolumes: add(\.persistentVolumes, namespaced: false)
            case .persistentVolumeClaims: add(\.persistentVolumeClaims)
            case .networkPolicies: add(\.networkPolicies)
            case .serviceAccounts: add(\.serviceAccounts)
            case .horizontalPodAutoscalers: add(\.horizontalPodAutoscalers)
            case .namespaces: add(\.namespaces, namespaced: false)
            case .endpoints: add(\.endpoints)
            }
        }
        if !viewModel.searchText.isEmpty {
            items = items.filter { $0.name.localizedCaseInsensitiveContains(viewModel.searchText) }
        }
        return items
    }

    private func clusterName(for clusterId: String) -> String {
        viewModel.availableConnections.first { $0.id == clusterId }?.name ?? clusterId
    }

    // MARK: - CRD Resource View

    @ViewBuilder
    private func crdResourceView(crd: CRDDefinition) -> some View {
        let allCrdItems = viewModel.selectedClusterIds.flatMap { viewModel.customResources[$0] ?? [] }
        let filtered = viewModel.searchText.isEmpty ? allCrdItems : allCrdItems.filter {
            $0.name.localizedCaseInsensitiveContains(viewModel.searchText)
        }

        if viewModel.isLoading && filtered.isEmpty {
            ProgressView("Loading \(crd.displayName)...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filtered.isEmpty {
            ContentUnavailableView(
                "No \(crd.displayName)",
                systemImage: "puzzlepiece.extension",
                description: Text("No custom resources found")
            )
        } else {
            Table(filtered) {
                TableColumn("Name") { item in
                    Text(item.name)
                        .fontWeight(.medium)
                        .foregroundStyle(Color(red: 0.29, green: 0.62, blue: 1.0))
                }
                .width(min: 150, ideal: 250)

                TableColumn("Namespace", value: \.namespace)
                    .width(min: 80, ideal: 120)

                TableColumn("Status") { item in
                    let phase = item.statusPhase
                    Text(phase.isEmpty ? "-" : phase)
                        .foregroundStyle(phase == "Ready" || phase == "Active" || phase == "Running" ? .green : .secondary)
                }
                .width(80)

                TableColumn("Age") { item in
                    Text(item.age)
                        .foregroundStyle(.secondary)
                }
                .width(50)

                TableColumn("API") { _ in
                    Text("\(crd.group)/\(crd.version)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .width(min: 100, ideal: 150)
            }
        }
    }

    // MARK: - Pod Metrics Helpers

    private func podMetrics(_ name: String, ns: String, clusterId: String) -> PodMetrics? {
        viewModel.podMetricsCache[clusterId]?.first { $0.name == name && $0.namespace == ns }
    }

    private func podCPU(_ name: String, ns: String, clusterId: String) -> Double? {
        guard let m = podMetrics(name, ns: ns, clusterId: clusterId) else { return nil }
        // Try to compute percentage from requests
        let used = m.totalCPU
        if let pod = viewModel.pods[clusterId]?.first(where: { $0.name == name }),
           let containers = pod.spec?.containers {
            let requested = containers.compactMap { $0.resources?.requests?["cpu"] }.reduce(0.0) { $0 + K8sQuantity.parseCPU($1) }
            if requested > 0 { return min(used / requested, 2.0) }
        }
        return nil // No percentage without requests, just show label
    }

    private func podCPULabel(_ name: String, ns: String, clusterId: String) -> String {
        guard let m = podMetrics(name, ns: ns, clusterId: clusterId) else { return "-" }
        let used = K8sQuantity.formatCPU(m.totalCPU)
        if let pod = viewModel.pods[clusterId]?.first(where: { $0.name == name }),
           let containers = pod.spec?.containers {
            let req = containers.compactMap { $0.resources?.requests?["cpu"] }.reduce(0.0) { $0 + K8sQuantity.parseCPU($1) }
            let lim = containers.compactMap { $0.resources?.limits?["cpu"] }.reduce(0.0) { $0 + K8sQuantity.parseCPU($1) }
            if lim > 0 { return "\(used)/\(K8sQuantity.formatCPU(lim))" }
            if req > 0 { return "\(used)/\(K8sQuantity.formatCPU(req))" }
        }
        return used
    }

    private func podMemory(_ name: String, ns: String, clusterId: String) -> Double? {
        guard let m = podMetrics(name, ns: ns, clusterId: clusterId) else { return nil }
        let used = m.totalMemory
        if let pod = viewModel.pods[clusterId]?.first(where: { $0.name == name }),
           let containers = pod.spec?.containers {
            let requested = containers.compactMap { $0.resources?.requests?["memory"] }.reduce(0.0) { $0 + K8sQuantity.parseMemory($1) }
            if requested > 0 { return min(used / requested, 2.0) }
            let limited = containers.compactMap { $0.resources?.limits?["memory"] }.reduce(0.0) { $0 + K8sQuantity.parseMemory($1) }
            if limited > 0 { return min(used / limited, 2.0) }
        }
        return nil
    }

    private func podMemoryLabel(_ name: String, ns: String, clusterId: String) -> String {
        guard let m = podMetrics(name, ns: ns, clusterId: clusterId) else { return "-" }
        let used = K8sQuantity.formatMemory(m.totalMemory)
        if let pod = viewModel.pods[clusterId]?.first(where: { $0.name == name }),
           let containers = pod.spec?.containers {
            let lim = containers.compactMap { $0.resources?.limits?["memory"] }.reduce(0.0) { $0 + K8sQuantity.parseMemory($1) }
            let req = containers.compactMap { $0.resources?.requests?["memory"] }.reduce(0.0) { $0 + K8sQuantity.parseMemory($1) }
            if lim > 0 { return "\(used)/\(K8sQuantity.formatMemory(lim))" }
            if req > 0 { return "\(used)/\(K8sQuantity.formatMemory(req))" }
        }
        return used
    }

    // MARK: - Node Metrics Helpers

    private func nodeMetrics(_ node: Node, clusterId: String) -> NodeMetrics? {
        viewModel.nodeMetricsCache[clusterId]?.first { $0.name == node.name }
    }

    private func nodeCPUPercent(_ node: Node, clusterId: String) -> Double? {
        guard let m = nodeMetrics(node, clusterId: clusterId),
              let capStr = node.status?.capacity?["cpu"] else { return nil }
        let capacity = K8sQuantity.parseCPU(capStr)
        guard capacity > 0 else { return nil }
        return m.cpuCores / capacity
    }

    private func nodeCPULabel(_ node: Node, clusterId: String) -> String {
        guard let m = nodeMetrics(node, clusterId: clusterId) else { return "-" }
        let capStr = node.status?.capacity?["cpu"] ?? ""
        let cap = K8sQuantity.parseCPU(capStr)
        if cap > 0 {
            return "\(K8sQuantity.formatCPU(m.cpuCores))/\(K8sQuantity.formatCPU(cap))"
        }
        return K8sQuantity.formatCPU(m.cpuCores)
    }

    private func nodeMemPercent(_ node: Node, clusterId: String) -> Double? {
        guard let m = nodeMetrics(node, clusterId: clusterId),
              let capStr = node.status?.capacity?["memory"] else { return nil }
        let capacity = K8sQuantity.parseMemory(capStr)
        guard capacity > 0 else { return nil }
        return m.memoryBytes / capacity
    }

    private func nodeMemLabel(_ node: Node, clusterId: String) -> String {
        guard let m = nodeMetrics(node, clusterId: clusterId) else { return "-" }
        let capStr = node.status?.capacity?["memory"] ?? ""
        let cap = K8sQuantity.parseMemory(capStr)
        if cap > 0 {
            return "\(K8sQuantity.formatMemory(m.memoryBytes))/\(K8sQuantity.formatMemory(cap))"
        }
        return K8sQuantity.formatMemory(m.memoryBytes)
    }
}

// MARK: - Mini Usage Bar (for table columns)

struct MiniUsageBar: View {
    let value: Double?  // 0.0-1.0+ (nil = no data)
    let label: String
    let color: Color

    var body: some View {
        if let pct = value {
            VStack(alignment: .leading, spacing: 1) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.primary.opacity(0.08))
                            .frame(height: 4)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(barColor(pct))
                            .frame(width: max(2, geo.size.width * min(pct, 1.0)), height: 4)
                    }
                }
                .frame(height: 4)
                Text(label)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } else {
            Text(label)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
    }

    private func barColor(_ pct: Double) -> Color {
        if pct > 0.9 { return .red }
        if pct > 0.7 { return .orange }
        return color
    }
}

// MARK: - Row Protocol & Types

protocol ResourceRow {
    var resourceId: ResourceIdentifier { get }
}

struct PodRow: Identifiable, ResourceRow { let id: ResourceIdentifier; let pod: Pod; let clusterId: String; var resourceId: ResourceIdentifier { id } }
struct DeploymentRow: Identifiable, ResourceRow { let id: ResourceIdentifier; let deployment: Deployment; let clusterId: String; var resourceId: ResourceIdentifier { id } }
struct ServiceRow: Identifiable, ResourceRow { let id: ResourceIdentifier; let service: Service; let clusterId: String; var resourceId: ResourceIdentifier { id } }
struct NodeRow: Identifiable, ResourceRow { let id: ResourceIdentifier; let node: Node; let clusterId: String; var resourceId: ResourceIdentifier { id } }
struct StatefulSetRow: Identifiable, ResourceRow { let id: ResourceIdentifier; let statefulSet: StatefulSet; let clusterId: String; var resourceId: ResourceIdentifier { id } }
struct DaemonSetRow: Identifiable, ResourceRow { let id: ResourceIdentifier; let daemonSet: DaemonSet; let clusterId: String; var resourceId: ResourceIdentifier { id } }
struct ReplicaSetRow: Identifiable, ResourceRow { let id: ResourceIdentifier; let replicaSet: ReplicaSet; let clusterId: String; var resourceId: ResourceIdentifier { id } }
struct JobRow: Identifiable, ResourceRow { let id: ResourceIdentifier; let job: Job; let clusterId: String; var resourceId: ResourceIdentifier { id } }
struct CronJobRow: Identifiable, ResourceRow { let id: ResourceIdentifier; let cronJob: CronJob; let clusterId: String; var resourceId: ResourceIdentifier { id } }
struct ConfigMapRow: Identifiable, ResourceRow { let id: ResourceIdentifier; let configMap: ConfigMap; let clusterId: String; var resourceId: ResourceIdentifier { id } }
struct SecretRow: Identifiable, ResourceRow { let id: ResourceIdentifier; let secret: Secret; let clusterId: String; var resourceId: ResourceIdentifier { id } }
struct IngressRow: Identifiable, ResourceRow { let id: ResourceIdentifier; let ingress: Ingress; let clusterId: String; var resourceId: ResourceIdentifier { id } }
struct IngressClassRow: Identifiable, ResourceRow { let id: ResourceIdentifier; let ingressClass: IngressClass; let clusterId: String; var resourceId: ResourceIdentifier { id } }
struct PersistentVolumeRow: Identifiable, ResourceRow { let id: ResourceIdentifier; let persistentVolume: PersistentVolume; let clusterId: String; var resourceId: ResourceIdentifier { id } }
struct PersistentVolumeClaimRow: Identifiable, ResourceRow { let id: ResourceIdentifier; let persistentVolumeClaim: PersistentVolumeClaim; let clusterId: String; var resourceId: ResourceIdentifier { id } }
struct NetworkPolicyRow: Identifiable, ResourceRow { let id: ResourceIdentifier; let networkPolicy: NetworkPolicy; let clusterId: String; var resourceId: ResourceIdentifier { id } }
struct ServiceAccountRow: Identifiable, ResourceRow { let id: ResourceIdentifier; let serviceAccount: ServiceAccount; let clusterId: String; var resourceId: ResourceIdentifier { id } }
struct HPARow: Identifiable, ResourceRow { let id: ResourceIdentifier; let hpa: HorizontalPodAutoscaler; let clusterId: String; var resourceId: ResourceIdentifier { id } }
struct NamespaceRow: Identifiable, ResourceRow { let id: ResourceIdentifier; let ns: Namespace; let clusterId: String; var resourceId: ResourceIdentifier { id } }
struct EndpointsRow: Identifiable, ResourceRow { let id: ResourceIdentifier; let endpoints: Endpoints; let clusterId: String; var resourceId: ResourceIdentifier { id } }
