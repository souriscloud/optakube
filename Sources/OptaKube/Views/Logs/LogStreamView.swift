import SwiftUI
import AppKit

struct LogStreamView: View {
    @Environment(AppViewModel.self) private var viewModel
    let resource: ResourceIdentifier
    @State private var logLines: [LogLine] = []
    @State private var isStreaming = false
    @State private var isLoadingInitial = true
    @State private var searchText = ""
    @State private var selectedContainer: String?
    @State private var autoScroll = true
    @State private var userScrolledUp = false
    @State private var streamTasks: [String: Task<Void, Never>] = [:]
    @State private var showTimestamps = false
    @State private var showPrevious = false
    @State private var additionalPodNames: [String] = []
    @State private var showAddPodPicker = false
    @State private var availablePodsInNamespace: [String] = []
    @State private var logCount: Int = 0
    @State private var logsPerSecond: Double = 0
    @State private var rateTimer: Task<Void, Never>?
    @State private var recentCount: Int = 0

    private static let podColors: [Color] = [
        .blue, .green, .orange, .purple, .pink,
        .cyan, .mint, .indigo, .brown, .teal
    ]

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    struct LogLine: Identifiable {
        let id: Int  // sequential index for stable identity
        let text: String
        let timestamp: Date
        let podName: String
    }

    private var allPodNames: [String] {
        [resource.name] + additionalPodNames
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            toolbar

            // Pod pills
            if !additionalPodNames.isEmpty {
                podPills
            }

            Divider()

            // Log content
            ZStack {
                logContent

                // "New logs" jump-to-bottom button when user scrolled up
                if userScrolledUp && isStreaming {
                    VStack {
                        Spacer()
                        Button {
                            autoScroll = true
                            userScrolledUp = false
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.down")
                                Text("New logs")
                                    .font(.caption)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                            .shadow(radius: 4)
                        }
                        .buttonStyle(.plain)
                        .padding(.bottom, 8)
                    }
                }

                // Initial loading
                if isLoadingInitial && logLines.isEmpty {
                    VStack(spacing: 8) {
                        ProgressView()
                        Text("Loading logs...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Divider()

            // Bottom status bar
            bottomBar
        }
        .onAppear {
            startStreaming()
            startRateCounter()
        }
        .onDisappear {
            stopAllStreams()
            rateTimer?.cancel()
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 6) {
            if let containers = findPod()?.spec?.containers, containers.count > 1 {
                Picker("Container", selection: $selectedContainer) {
                    Text("All").tag(nil as String?)
                    ForEach(containers) { c in
                        Text(c.name).tag(c.name as String?)
                    }
                }
                .frame(width: 120)
            }

            Spacer()

            Toggle(isOn: $showTimestamps) {
                Image(systemName: "clock")
            }
            .toggleStyle(.button)
            .controlSize(.small)
            .help("Timestamps")

            Toggle(isOn: $showPrevious) {
                Image(systemName: "arrow.counterclockwise")
            }
            .toggleStyle(.button)
            .controlSize(.small)
            .help("Previous container")
            .onChange(of: showPrevious) { _, _ in
                restartAllStreams()
            }

            Toggle(isOn: $autoScroll) {
                Image(systemName: "arrow.down.to.line")
            }
            .toggleStyle(.button)
            .controlSize(.small)
            .help("Auto-scroll")
            .onChange(of: autoScroll) { _, newValue in
                if newValue { userScrolledUp = false }
            }

            Divider().frame(height: 16)

            Button {
                showAddPodPicker.toggle()
                if showAddPodPicker { loadAvailablePods() }
            } label: {
                Image(systemName: "plus.circle")
            }
            .help("Add pod")
            .popover(isPresented: $showAddPodPicker) {
                addPodPopover
            }

            Button {
                if isStreaming { stopAllStreams() } else { startStreaming() }
            } label: {
                Image(systemName: isStreaming ? "stop.fill" : "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(isStreaming ? .red : .blue)

            Button { exportLogs() } label: { Image(systemName: "square.and.arrow.up") }.help("Export")
            Button { logLines.removeAll(); logCount = 0 } label: { Image(systemName: "trash") }.help("Clear")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    // MARK: - Pod Pills

    private var podPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(allPodNames, id: \.self) { podName in
                    HStack(spacing: 4) {
                        Circle().fill(colorForPod(podName)).frame(width: 8, height: 8)
                        Text(podName).font(.caption)
                        if podName != resource.name {
                            Button { removePod(podName) } label: {
                                Image(systemName: "xmark.circle.fill").font(.caption2)
                            }.buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(colorForPod(podName).opacity(0.15))
                    .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
        }
    }

    // MARK: - Log Content

    private var logContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(filteredLines) { line in
                        logLineView(line)
                            .id(line.id)
                    }

                    // Bottom sentinel — when visible, user is at bottom
                    Color.clear.frame(height: 1)
                        .id("bottom")
                        .onAppear { userScrolledUp = false }
                        .onDisappear {
                            if isStreaming { userScrolledUp = true; autoScroll = false }
                        }
                }
                .padding(.vertical, 4)
            }
            .onChange(of: logLines.count) { _, _ in
                if autoScroll {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }

    // MARK: - Bottom Bar (search + stats)

    private var bottomBar: some View {
        HStack(spacing: 8) {
            // Search
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                TextField("Find in logs...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(.caption, design: .monospaced))
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").font(.caption)
                    }
                    .buttonStyle(.plain)
                    Text("\(filteredLines.count) matches")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            Spacer()

            // Stats
            HStack(spacing: 12) {
                if logsPerSecond > 0 {
                    Text("\(String(format: "%.0f", logsPerSecond))/s")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Text("\(logCount) lines")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.bar)
    }

    // MARK: - Log Line View

    @ViewBuilder
    private func logLineView(_ line: LogLine) -> some View {
        HStack(spacing: 0) {
            if showTimestamps {
                Text(Self.timestampFormatter.string(from: line.timestamp))
                    .foregroundStyle(.secondary)
                    .font(.system(.caption2, design: .monospaced))
                Text(" ")
            }
            if allPodNames.count > 1 {
                Text(shortPodName(line.podName))
                    .foregroundStyle(colorForPod(line.podName))
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.medium)
                Text(" │ ")
                    .foregroundStyle(Color.gray.opacity(0.3))
                    .font(.system(.caption, design: .monospaced))
            }
            if searchText.isEmpty {
                Text(line.text)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            } else {
                Text(highlightedText(line.text))
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 1)
        .background(line.id % 2 == 0 ? Color.clear : Color.primary.opacity(0.02))
    }

    private func shortPodName(_ name: String) -> String {
        // Show last 5 chars of pod name for compact display
        if name.count > 8 {
            return String(name.suffix(5))
        }
        return name
    }

    // MARK: - Add Pod Popover

    @State private var podFilterText: String = ""

    private var filteredAvailablePods: [String] {
        if podFilterText.isEmpty { return availablePodsInNamespace }
        return availablePodsInNamespace.filter { $0.localizedCaseInsensitiveContains(podFilterText) }
    }

    @ViewBuilder
    private var addPodPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Add Pod")
                    .font(.headline)
                Spacer()
                Text("\(availablePodsInNamespace.count) pods")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Search field
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                TextField("Filter pods...", text: $podFilterText)
                    .textFieldStyle(.plain)
                    .font(.subheadline)
                if !podFilterText.isEmpty {
                    Button { podFilterText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            Divider()

            // Pod list
            if filteredAvailablePods.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 4) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.tertiary)
                        Text(availablePodsInNamespace.isEmpty ? "No other pods in namespace" : "No pods matching \"\(podFilterText)\"")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 16)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredAvailablePods, id: \.self) { podName in
                            let isAdded = allPodNames.contains(podName)
                            Button {
                                if !isAdded {
                                    additionalPodNames.append(podName)
                                    startStreamForPod(podName)
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: isAdded ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(isAdded ? .green : .secondary)
                                        .font(.subheadline)

                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(podName)
                                            .font(.subheadline)
                                            .foregroundStyle(isAdded ? .secondary : .primary)
                                            .lineLimit(1)
                                    }

                                    Spacer()
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .background(isAdded ? Color.green.opacity(0.05) : Color.clear)

                            if podName != filteredAvailablePods.last {
                                Divider().padding(.leading, 40)
                            }
                        }
                    }
                }
                .frame(maxHeight: 280)
            }
        }
        .frame(width: 320)
        .onAppear { podFilterText = "" }
    }

    // MARK: - Filtering

    private var filteredLines: [LogLine] {
        if searchText.isEmpty { return logLines }
        return logLines.filter { $0.text.localizedCaseInsensitiveContains(searchText) }
    }

    private func highlightedText(_ text: String) -> AttributedString {
        var attributed = AttributedString(text)
        if !searchText.isEmpty, let range = attributed.range(of: searchText, options: .caseInsensitive) {
            attributed[range].backgroundColor = .yellow
            attributed[range].foregroundColor = .black
        }
        return attributed
    }

    private func colorForPod(_ podName: String) -> Color {
        guard let idx = allPodNames.firstIndex(of: podName) else { return .primary }
        return Self.podColors[idx % Self.podColors.count]
    }

    // MARK: - Streaming

    private func startStreaming() {
        startAllStreams()
    }

    private func startAllStreams() {
        for podName in allPodNames {
            startStreamForPod(podName)
        }
    }

    private func stopAllStreams() {
        for (_, task) in streamTasks { task.cancel() }
        streamTasks.removeAll()
        isStreaming = false
    }

    private func restartAllStreams() {
        stopAllStreams()
        logLines.removeAll()
        logCount = 0
        isLoadingInitial = true
        startAllStreams()
    }

    private func startStreamForPod(_ podName: String) {
        guard let client = viewModel.activeClients[resource.clusterId],
              let namespace = resource.namespace else { return }

        isStreaming = true
        let task = Task {
            do {
                let stream = client.streamLogs(
                    namespace: namespace,
                    podName: podName,
                    container: selectedContainer,
                    tailLines: 500,
                    previous: showPrevious
                )
                var lineIndex = logCount
                for try await line in stream {
                    await MainActor.run {
                        isLoadingInitial = false
                        let logLine = LogLine(id: lineIndex, text: line, timestamp: Date(), podName: podName)
                        logLines.append(logLine)
                        lineIndex += 1
                        logCount = lineIndex
                        recentCount += 1

                        // Cap at 10000 lines
                        if logLines.count > 10000 {
                            logLines.removeFirst(logLines.count - 10000)
                        }
                    }
                }
            } catch {
                // Stream ended
            }
            await MainActor.run {
                isLoadingInitial = false
                streamTasks.removeValue(forKey: podName)
                if streamTasks.isEmpty { isStreaming = false }
            }
        }
        streamTasks[podName] = task
    }

    private func removePod(_ podName: String) {
        additionalPodNames.removeAll { $0 == podName }
        if let task = streamTasks.removeValue(forKey: podName) { task.cancel() }
    }

    // MARK: - Rate Counter

    private func startRateCounter() {
        rateTimer = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                await MainActor.run {
                    logsPerSecond = Double(recentCount) / 2.0
                    recentCount = 0
                }
            }
        }
    }

    // MARK: - Load Available Pods

    private func loadAvailablePods() {
        guard let client = viewModel.activeClients[resource.clusterId],
              let namespace = resource.namespace else { return }
        Task {
            if let pods = try? await client.list(Pod.self, resourceType: .pods, namespace: namespace) {
                let names = pods.map(\.name).filter { !allPodNames.contains($0) }.sorted()
                await MainActor.run { availablePodsInNamespace = names }
            }
        }
    }

    // MARK: - Export

    private func exportLogs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "\(resource.name)-logs.log"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let lines = filteredLines.map { line in
            var prefix = ""
            if showTimestamps { prefix += Self.timestampFormatter.string(from: line.timestamp) + " " }
            if allPodNames.count > 1 { prefix += line.podName + " | " }
            return prefix + line.text
        }
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private func findPod() -> Pod? {
        viewModel.pods[resource.clusterId]?.first { $0.name == resource.name }
    }
}
