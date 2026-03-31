import SwiftUI
import AppKit

// MARK: - Log Line Model

struct LogLine: Identifiable {
    let id: Int
    let text: String
    let timestamp: Date
    let podName: String
    let containerName: String
    var isMark: Bool = false  // Visual separator mark (Space key)

    /// Detect if the log line is JSON
    var isJSON: Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("{") && trimmed.hasSuffix("}")
    }

    /// Detect if logfmt (key=value pairs)
    var isLogfmt: Bool {
        let parts = text.split(separator: " ")
        let kvCount = parts.filter { $0.contains("=") }.count
        return kvCount >= 2 && kvCount > parts.count / 3
    }
}

// MARK: - Container Toggle State

struct ContainerToggle: Identifiable {
    let id: String  // "podName/containerName"
    let podName: String
    let containerName: String
    var enabled: Bool
    let isInit: Bool
}

// MARK: - Timestamp Mode

enum TimestampMode: String, CaseIterable {
    case off = "Off"
    case local = "Local"
    case utc = "UTC"
}

// MARK: - Log Font Size

enum LogFontSize: String, CaseIterable {
    case small = "Small"
    case medium = "Default"
    case large = "Large"

    var size: CGFloat {
        switch self {
        case .small: return 10
        case .medium: return 12
        case .large: return 14
        }
    }
}

// MARK: - Main Log Stream View

struct LogStreamView: View {
    @Environment(AppViewModel.self) private var viewModel
    let resource: ResourceIdentifier
    var isFullWindow: Bool = false

    // Log data
    @State private var logLines: [LogLine] = []
    @State private var logCounter: Int = 0

    // Streaming state
    @State private var isStreaming = false
    @State private var isLoadingInitial = true
    @State private var streamTasks: [String: Task<Void, Never>] = [:]

    // Container toggles
    @State private var containerToggles: [ContainerToggle] = []
    @State private var showContainerPicker = false

    // Additional pods
    @State private var additionalPodNames: [String] = []
    @State private var showAddPodPicker = false
    @State private var availablePodsInNamespace: [String] = []
    @State private var podFilterText: String = ""

    // Search
    @State private var searchText: String = ""
    @State private var searchMatchIndices: [Int] = []
    @State private var currentMatchIndex: Int = 0
    @State private var searchMode: SearchMode = .highlight

    // Display settings
    @State private var timestampMode: TimestampMode = .off
    @State private var lineWrap: Bool = true
    @State private var fontSize: LogFontSize = .medium
    @State private var showPrevious: Bool = false
    @State private var syntaxHighlight: Bool = true

    // Scroll
    @State private var autoScroll: Bool = true
    @State private var userScrolledUp: Bool = false

    // Stats
    @State private var logsPerSecond: Double = 0
    @State private var rateTimer: Task<Void, Never>?
    @State private var recentCount: Int = 0

    enum SearchMode: String, CaseIterable {
        case highlight = "Highlight"
        case filter = "Filter"
    }

    private static let podColors: [Color] = [
        .blue, .green, .orange, .purple, .pink, .cyan, .mint, .indigo, .brown, .teal
    ]

    private static let localFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    private static let utcFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    private var allPodNames: [String] {
        [resource.name] + additionalPodNames
    }

    private var enabledContainerIds: Set<String> {
        Set(containerToggles.filter(\.enabled).map(\.id))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top toolbar
            topToolbar

            // Container/Pod selector bar
            if containerToggles.count > 1 || !additionalPodNames.isEmpty {
                containerBar
                Divider()
            }

            // Log content
            ZStack(alignment: .bottom) {
                logContent

                // Jump to bottom
                if userScrolledUp && isStreaming {
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
                        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 8)
                }

                // Loading
                if isLoadingInitial && logLines.isEmpty {
                    VStack(spacing: 8) {
                        ProgressView()
                        Text("Connecting to log stream...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Divider()

            // Bottom bar (search + stats)
            bottomBar
        }
        .background(Color(nsColor: .textBackgroundColor))
        .onAppear {
            initContainerToggles()
            startStreaming()
            startRateCounter()
        }
        .onDisappear {
            stopAllStreams()
            rateTimer?.cancel()
        }
        .onKeyPress(.space) {
            insertMark()
            return .handled
        }
    }

    // MARK: - Top Toolbar

    private var topToolbar: some View {
        HStack(spacing: 6) {
            // Container picker button
            Button {
                showContainerPicker.toggle()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "square.stack")
                    Text("\(containerToggles.filter(\.enabled).count)/\(containerToggles.count)")
                        .font(.caption)
                }
            }
            .controlSize(.small)
            .popover(isPresented: $showContainerPicker) { containerPickerPopover }
            .help("Select containers")

            // Add pod
            Button {
                showAddPodPicker.toggle()
                if showAddPodPicker { loadAvailablePods() }
            } label: {
                Image(systemName: "plus.circle")
            }
            .controlSize(.small)
            .help("Add pod to stream")
            .popover(isPresented: $showAddPodPicker) { addPodPopover }

            Divider().frame(height: 16)

            // Timestamp mode
            Picker("", selection: $timestampMode) {
                ForEach(TimestampMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 140)
            .help("Timestamp display")

            Divider().frame(height: 16)

            // Line wrap
            Toggle(isOn: $lineWrap) {
                Image(systemName: "text.word.spacing")
            }
            .toggleStyle(.button)
            .controlSize(.small)
            .help("Line wrap")

            // Syntax highlighting
            Toggle(isOn: $syntaxHighlight) {
                Image(systemName: "paintbrush")
            }
            .toggleStyle(.button)
            .controlSize(.small)
            .help("JSON/logfmt highlighting")

            // Previous container
            Toggle(isOn: $showPrevious) {
                Image(systemName: "arrow.counterclockwise")
            }
            .toggleStyle(.button)
            .controlSize(.small)
            .help("Previous container logs")
            .onChange(of: showPrevious) { _, _ in restartAllStreams() }

            // Font size
            Menu {
                ForEach(LogFontSize.allCases, id: \.self) { size in
                    Button {
                        fontSize = size
                    } label: {
                        HStack {
                            Text(size.rawValue)
                            if fontSize == size { Image(systemName: "checkmark") }
                        }
                    }
                }
            } label: {
                Image(systemName: "textformat.size")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 28)
            .help("Font size")

            Spacer()

            // Open in dedicated window (not full-window mode which is same window)
            if !isFullWindow {
                Button {
                    openLogsInWindow()
                } label: {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                }
                .controlSize(.small)
                .help("Open logs in separate window")
            }

            // Stream controls
            Button {
                if isStreaming { stopAllStreams() } else { startStreaming() }
            } label: {
                Image(systemName: isStreaming ? "stop.fill" : "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(isStreaming ? .red : .blue)

            Button { exportLogs() } label: { Image(systemName: "square.and.arrow.up") }
                .controlSize(.small).help("Export")
            Button { logLines.removeAll(); logCounter = 0 } label: { Image(systemName: "trash") }
                .controlSize(.small).help("Clear")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.bar)
    }

    // MARK: - Container/Pod Bar

    private var containerBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(allPodNames, id: \.self) { podName in
                    let containers = containerToggles.filter { $0.podName == podName }
                    ForEach(containers) { ct in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(ct.enabled ? colorForPod(ct.podName) : Color.gray)
                                .frame(width: 6, height: 6)
                            if ct.isInit {
                                Text("init:")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.tertiary)
                            }
                            Text(containers.count > 1 ? "\(shortPodName(ct.podName))/\(ct.containerName)" : shortPodName(ct.podName))
                                .font(.caption2)
                                .foregroundStyle(ct.enabled ? .primary : .tertiary)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(ct.enabled ? colorForPod(ct.podName).opacity(0.12) : Color.gray.opacity(0.05))
                        .clipShape(Capsule())
                        .onTapGesture {
                            if let idx = containerToggles.firstIndex(where: { $0.id == ct.id }) {
                                containerToggles[idx].enabled.toggle()
                            }
                        }
                    }

                    if podName != resource.name {
                        Button {
                            removePod(podName)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
        }
    }

    // MARK: - Log Content

    @State private var lastRenderedCount: Int = 0

    private var logContent: some View {
        ScrollViewReader { proxy in
            ScrollView(lineWrap ? .vertical : [.vertical, .horizontal]) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(displayLines) { line in
                        if line.isMark {
                            markView.id(line.id)
                        } else {
                            logLineView(line).id(line.id)
                        }
                    }

                    // Anchor at the very bottom
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.vertical, 2)
            }
            .onChange(of: logLines.count) { oldCount, newCount in
                // Only scroll if user hasn't scrolled away
                if autoScroll {
                    proxy.scrollTo("bottom", anchor: .bottom)
                } else {
                    // User is reading — don't scroll, but show the "New logs" badge
                    userScrolledUp = true
                }
            }
            .onChange(of: currentMatchIndex) { _, _ in
                scrollToCurrentMatch(proxy: proxy)
            }
            .onChange(of: autoScroll) { _, newValue in
                if newValue {
                    userScrolledUp = false
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            // Detect user scrolling via gesture
            .simultaneousGesture(
                DragGesture(minimumDistance: 5)
                    .onChanged { _ in
                        // User is manually scrolling
                        if autoScroll {
                            autoScroll = false
                            userScrolledUp = true
                        }
                    }
            )
        }
    }

    private var markView: some View {
        HStack {
            VStack { Divider() }
            Text("MARK")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.orange)
                .padding(.horizontal, 6)
            VStack { Divider() }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
    }

    // MARK: - Log Line Rendering

    @ViewBuilder
    private func logLineView(_ line: LogLine) -> some View {
        let isMatch = !searchText.isEmpty && line.text.localizedCaseInsensitiveContains(searchText)
        let isCurrentMatch = searchMatchIndices.indices.contains(currentMatchIndex) && searchMatchIndices[currentMatchIndex] == line.id

        HStack(alignment: .top, spacing: 0) {
            // Timestamp
            if timestampMode != .off {
                let formatter = timestampMode == .utc ? Self.utcFormatter : Self.localFormatter
                Text(formatter.string(from: line.timestamp))
                    .foregroundStyle(.secondary)
                    .font(.system(size: fontSize.size - 2, design: .monospaced))
                Text(" ")
                    .font(.system(size: fontSize.size, design: .monospaced))
            }

            // Pod/container prefix
            if allPodNames.count > 1 || containerToggles.count > 1 {
                Text(shortPodName(line.podName))
                    .foregroundStyle(colorForPod(line.podName))
                    .font(.system(size: fontSize.size, weight: .medium, design: .monospaced))
                if containerToggles.filter({ $0.podName == line.podName }).count > 1 {
                    Text("/\(line.containerName)")
                        .foregroundStyle(colorForPod(line.podName).opacity(0.6))
                        .font(.system(size: fontSize.size - 1, design: .monospaced))
                }
                Text(" │ ")
                    .foregroundStyle(Color.gray.opacity(0.25))
                    .font(.system(size: fontSize.size, design: .monospaced))
            }

            // Log text with optional syntax highlighting
            if syntaxHighlight && line.isJSON {
                Text(jsonHighlighted(line.text, searchTerm: searchText))
                    .font(.system(size: fontSize.size, design: .monospaced))
                    .textSelection(.enabled)
            } else if syntaxHighlight && line.isLogfmt {
                Text(logfmtHighlighted(line.text, searchTerm: searchText))
                    .font(.system(size: fontSize.size, design: .monospaced))
                    .textSelection(.enabled)
            } else if !searchText.isEmpty {
                Text(searchHighlighted(line.text))
                    .font(.system(size: fontSize.size, design: .monospaced))
                    .textSelection(.enabled)
            } else {
                Text(ansiStripped(line.text))
                    .font(.system(size: fontSize.size, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: lineWrap ? .infinity : nil, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 1)
        .background(
            isCurrentMatch ? Color.yellow.opacity(0.2) :
                isMatch ? Color.yellow.opacity(0.08) :
                line.id % 2 == 0 ? Color.clear : Color.primary.opacity(0.02)
        )
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack(spacing: 6) {
            // Search mode toggle
            Picker("", selection: $searchMode) {
                ForEach(SearchMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 130)

            // Search field
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                TextField("Find in logs...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(.caption, design: .monospaced))
                    .onSubmit { nextMatch() }
                if !searchText.isEmpty {
                    Text("\(searchMatchIndices.isEmpty ? 0 : currentMatchIndex + 1)/\(searchMatchIndices.count)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 35)
                    Button { previousMatch() } label: {
                        Image(systemName: "chevron.up").font(.system(size: 9))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut("g", modifiers: [.command, .shift])
                    Button { nextMatch() } label: {
                        Image(systemName: "chevron.down").font(.system(size: 9))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut("g", modifiers: .command)
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.primary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            Spacer()

            // Stats
            if logsPerSecond > 0 {
                Text("\(String(format: "%.0f", logsPerSecond))/s")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            Text("\(logLines.filter({ !$0.isMark }).count) lines")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)

            // Connection indicator
            if isStreaming {
                HStack(spacing: 3) {
                    Circle().fill(.green).frame(width: 5, height: 5)
                    Text("Live")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.bar)
        .onChange(of: searchText) { _, _ in updateSearchMatches() }
    }

    // MARK: - Display Lines (filtered)

    private var displayLines: [LogLine] {
        var lines = logLines.filter { line in
            if line.isMark { return true }
            return enabledContainerIds.contains("\(line.podName)/\(line.containerName)")
        }
        if searchMode == .filter && !searchText.isEmpty {
            lines = lines.filter { $0.isMark || $0.text.localizedCaseInsensitiveContains(searchText) }
        }
        return lines
    }

    // MARK: - Search Navigation

    private func updateSearchMatches() {
        guard !searchText.isEmpty else { searchMatchIndices = []; return }
        searchMatchIndices = displayLines.filter {
            !$0.isMark && $0.text.localizedCaseInsensitiveContains(searchText)
        }.map(\.id)
        currentMatchIndex = max(0, searchMatchIndices.count - 1) // Start from last match
    }

    private func nextMatch() {
        guard !searchMatchIndices.isEmpty else { return }
        currentMatchIndex = (currentMatchIndex + 1) % searchMatchIndices.count
    }

    private func previousMatch() {
        guard !searchMatchIndices.isEmpty else { return }
        currentMatchIndex = (currentMatchIndex - 1 + searchMatchIndices.count) % searchMatchIndices.count
    }

    private func scrollToCurrentMatch(proxy: ScrollViewProxy) {
        guard searchMatchIndices.indices.contains(currentMatchIndex) else { return }
        let lineId = searchMatchIndices[currentMatchIndex]
        withAnimation(.easeOut(duration: 0.15)) {
            proxy.scrollTo(lineId, anchor: .center)
        }
        autoScroll = false
    }

    // MARK: - Visual Mark

    private func insertMark() {
        logCounter += 1
        logLines.append(LogLine(id: logCounter, text: "", timestamp: Date(), podName: "", containerName: "", isMark: true))
    }

    // MARK: - Syntax Highlighting

    private func jsonHighlighted(_ text: String, searchTerm: String) -> AttributedString {
        var result = AttributedString()
        var i = text.startIndex
        while i < text.endIndex {
            let ch = text[i]
            if ch == "\"" {
                if let end = findEndOfString(text, from: i) {
                    let raw = String(text[i...end])
                    var attr = AttributedString(raw)
                    // Check if key (followed by colon)
                    var afterStr = text.index(after: end)
                    while afterStr < text.endIndex && text[afterStr].isWhitespace { afterStr = text.index(after: afterStr) }
                    if afterStr < text.endIndex && text[afterStr] == ":" {
                        attr.foregroundColor = .teal
                    } else {
                        attr.foregroundColor = .green
                    }
                    result.append(attr)
                    i = text.index(after: end)
                    continue
                }
            }
            if ch == "{" || ch == "}" || ch == "[" || ch == "]" || ch == ":" || ch == "," {
                var attr = AttributedString(String(ch))
                attr.foregroundColor = .gray
                result.append(attr)
            } else if ch.isNumber || ch == "-" || ch == "." {
                var tokenEnd = text.index(after: i)
                while tokenEnd < text.endIndex && (text[tokenEnd].isNumber || text[tokenEnd] == "." || text[tokenEnd] == "e" || text[tokenEnd] == "E" || text[tokenEnd] == "-" || text[tokenEnd] == "+") {
                    tokenEnd = text.index(after: tokenEnd)
                }
                let token = String(text[i..<tokenEnd])
                if Double(token) != nil {
                    var attr = AttributedString(token)
                    attr.foregroundColor = .orange
                    result.append(attr)
                    i = tokenEnd
                    continue
                } else {
                    result.append(AttributedString(String(ch)))
                }
            } else {
                let s = String(ch)
                if s == "t" || s == "f" || s == "n" {
                    // Check for true/false/null
                    for keyword in ["true", "false", "null"] {
                        if text[i...].hasPrefix(keyword) {
                            var attr = AttributedString(keyword)
                            attr.foregroundColor = .purple
                            result.append(attr)
                            i = text.index(i, offsetBy: keyword.count)
                            break
                        }
                    }
                    if i <= text.index(before: text.endIndex) && (text[i...].hasPrefix("true") || text[i...].hasPrefix("false") || text[i...].hasPrefix("null")) {
                        continue
                    }
                    result.append(AttributedString(s))
                } else {
                    result.append(AttributedString(s))
                }
            }
            i = text.index(after: i)
        }
        // Apply search highlights
        if !searchTerm.isEmpty, let range = result.range(of: searchTerm, options: .caseInsensitive) {
            result[range].backgroundColor = .yellow
            result[range].foregroundColor = .black
        }
        return result
    }

    private func logfmtHighlighted(_ text: String, searchTerm: String) -> AttributedString {
        var result = AttributedString()
        let parts = text.split(separator: " ", omittingEmptySubsequences: false)
        for (idx, part) in parts.enumerated() {
            if idx > 0 { result.append(AttributedString(" ")) }
            if let eqIdx = part.firstIndex(of: "=") {
                let key = String(part[part.startIndex..<eqIdx])
                let val = String(part[part.index(after: eqIdx)...])
                var keyAttr = AttributedString(key)
                keyAttr.foregroundColor = .teal
                var eqAttr = AttributedString("=")
                eqAttr.foregroundColor = .gray
                var valAttr = AttributedString(val)
                if val.hasPrefix("\"") { valAttr.foregroundColor = .green }
                else if Double(val) != nil { valAttr.foregroundColor = .orange }
                else if val == "true" || val == "false" { valAttr.foregroundColor = .purple }
                result.append(keyAttr)
                result.append(eqAttr)
                result.append(valAttr)
            } else {
                result.append(AttributedString(String(part)))
            }
        }
        if !searchTerm.isEmpty, let range = result.range(of: searchTerm, options: .caseInsensitive) {
            result[range].backgroundColor = .yellow
            result[range].foregroundColor = .black
        }
        return result
    }

    private func searchHighlighted(_ text: String) -> AttributedString {
        var attr = AttributedString(ansiStripped(text))
        if !searchText.isEmpty, let range = attr.range(of: searchText, options: .caseInsensitive) {
            attr[range].backgroundColor = .yellow
            attr[range].foregroundColor = .black
        }
        return attr
    }

    private func ansiStripped(_ text: String) -> String {
        // Strip ANSI escape sequences
        var result = ""
        var i = text.startIndex
        while i < text.endIndex {
            if text[i] == "\u{1b}" {
                i = text.index(after: i)
                if i < text.endIndex && text[i] == "[" {
                    i = text.index(after: i)
                    while i < text.endIndex && !text[i].isLetter { i = text.index(after: i) }
                    if i < text.endIndex { i = text.index(after: i) }
                } else if i < text.endIndex {
                    i = text.index(after: i)
                }
            } else {
                result.append(text[i])
                i = text.index(after: i)
            }
        }
        return result
    }

    private func findEndOfString(_ str: String, from start: String.Index) -> String.Index? {
        guard str[start] == "\"" else { return nil }
        var i = str.index(after: start)
        while i < str.endIndex {
            if str[i] == "\\" { i = str.index(after: i); if i < str.endIndex { i = str.index(after: i) } }
            else if str[i] == "\"" { return i }
            else { i = str.index(after: i) }
        }
        return nil
    }

    // MARK: - Container Toggle Init

    private func initContainerToggles() {
        guard containerToggles.isEmpty else { return }
        guard let pod = findPod() else { return }
        var toggles: [ContainerToggle] = []

        // Init containers
        for c in pod.spec?.initContainers ?? [] {
            toggles.append(ContainerToggle(id: "\(resource.name)/\(c.name)", podName: resource.name, containerName: c.name, enabled: false, isInit: true))
        }
        // Regular containers
        for c in pod.spec?.containers ?? [] {
            toggles.append(ContainerToggle(id: "\(resource.name)/\(c.name)", podName: resource.name, containerName: c.name, enabled: true, isInit: false))
        }
        containerToggles = toggles
    }

    // MARK: - Container Picker Popover

    @ViewBuilder
    private var containerPickerPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Containers").font(.headline)
                Spacer()
                Button("All") {
                    for i in containerToggles.indices { containerToggles[i].enabled = true }
                }
                .font(.caption)
                Button("None") {
                    for i in containerToggles.indices { containerToggles[i].enabled = false }
                }
                .font(.caption)
            }

            Divider()

            ForEach(containerToggles.indices, id: \.self) { idx in
                let ct = containerToggles[idx]
                HStack(spacing: 8) {
                    Image(systemName: ct.enabled ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(ct.enabled ? colorForPod(ct.podName) : .secondary)
                    if ct.isInit {
                        Text("init: \(ct.containerName)")
                            .font(.subheadline)
                            .italic()
                    } else {
                        Text(ct.containerName)
                            .font(.subheadline)
                    }
                    Spacer()
                    Text(ct.podName)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
                .onTapGesture { containerToggles[idx].enabled.toggle() }
            }
        }
        .padding()
        .frame(width: 300)
    }

    // MARK: - Add Pod Popover

    private var filteredAvailablePods: [String] {
        if podFilterText.isEmpty { return availablePodsInNamespace }
        return availablePodsInNamespace.filter { $0.localizedCaseInsensitiveContains(podFilterText) }
    }

    @ViewBuilder
    private var addPodPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Add Pod").font(.headline)
                Spacer()
                Text("\(availablePodsInNamespace.count) pods").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.caption)
                TextField("Filter pods...", text: $podFilterText).textFieldStyle(.plain).font(.subheadline)
                if !podFilterText.isEmpty {
                    Button { podFilterText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary).font(.caption)
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            Divider()

            if filteredAvailablePods.isEmpty {
                Text(availablePodsInNamespace.isEmpty ? "No other pods" : "No match")
                    .foregroundStyle(.secondary).font(.caption).padding()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredAvailablePods, id: \.self) { podName in
                            let isAdded = allPodNames.contains(podName)
                            Button {
                                if !isAdded {
                                    additionalPodNames.append(podName)
                                    addContainerTogglesAndStream(podName)
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: isAdded ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(isAdded ? .green : .secondary)
                                    Text(podName).font(.subheadline).foregroundStyle(isAdded ? .secondary : .primary).lineLimit(1)
                                    Spacer()
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 5)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 400)
            }
        }
        .frame(width: 340)
        .onAppear { podFilterText = "" }
    }

    // MARK: - Streaming

    private func startStreaming() {
        for podName in allPodNames {
            startStreamForPod(podName)
        }
    }

    private func startStreamForPod(_ podName: String) {
        guard let client = viewModel.activeClients[resource.clusterId],
              let namespace = resource.namespace else { return }

        let containers = containerToggles.filter { $0.podName == podName && $0.enabled }
        let containerNames = containers.isEmpty ? [nil as String?] : containers.map { $0.containerName as String? }

        for containerName in containerNames {
            let streamKey = "\(podName)/\(containerName ?? "all")"
            guard streamTasks[streamKey] == nil else { continue }

            isStreaming = true
            let task = Task {
                var retries = 0
                while !Task.isCancelled && retries < 3 {
                    do {
                        let stream = client.streamLogs(
                            namespace: namespace,
                            podName: podName,
                            container: containerName,
                            tailLines: 500,
                            previous: showPrevious
                        )
                        retries = 0

                        // Buffer initial history lines for sorting
                        var historyBuffer: [(Date, String)] = []
                        var isHistory = true
                        let historyDeadline = Date().addingTimeInterval(2) // 2s to collect history

                        for try await (timestamp, line) in stream {
                            if isHistory && Date() < historyDeadline {
                                historyBuffer.append((timestamp, line))
                            } else {
                                // Flush sorted history buffer on first live line
                                if isHistory {
                                    isHistory = false
                                    let sorted = historyBuffer.sorted { $0.0 < $1.0 }
                                    await MainActor.run {
                                        isLoadingInitial = false
                                        for (ts, msg) in sorted {
                                            logCounter += 1
                                            logLines.append(LogLine(id: logCounter, text: msg, timestamp: ts, podName: podName, containerName: containerName ?? "default"))
                                        }
                                        // Sort all existing lines by timestamp (merges multiple pods' history)
                                        let marks = logLines.filter(\.isMark)
                                        var nonMarks = logLines.filter { !$0.isMark }
                                        nonMarks.sort { $0.timestamp < $1.timestamp }
                                        // Re-assign sequential IDs after sort
                                        logCounter = 0
                                        logLines = (nonMarks + marks).enumerated().map { idx, line in
                                            LogLine(id: idx + 1, text: line.text, timestamp: line.timestamp, podName: line.podName, containerName: line.containerName, isMark: line.isMark)
                                        }
                                        logCounter = logLines.count
                                        recentCount += sorted.count
                                    }
                                }

                                // Live line — append directly
                                await MainActor.run {
                                    logCounter += 1
                                    logLines.append(LogLine(id: logCounter, text: line, timestamp: timestamp, podName: podName, containerName: containerName ?? "default"))
                                    recentCount += 1
                                    if logLines.count > 15000 {
                                        logLines.removeFirst(logLines.count - 12000)
                                    }
                                }
                            }
                        }

                        // Flush remaining history if stream ended during history phase
                        if isHistory && !historyBuffer.isEmpty {
                            let sorted = historyBuffer.sorted { $0.0 < $1.0 }
                            await MainActor.run {
                                isLoadingInitial = false
                                for (ts, msg) in sorted {
                                    logCounter += 1
                                    logLines.append(LogLine(id: logCounter, text: msg, timestamp: ts, podName: podName, containerName: containerName ?? "default"))
                                }
                                // Sort all lines by timestamp
                                var nonMarks = logLines.filter { !$0.isMark }
                                nonMarks.sort { $0.timestamp < $1.timestamp }
                                logCounter = 0
                                logLines = nonMarks.enumerated().map { idx, line in
                                    LogLine(id: idx + 1, text: line.text, timestamp: line.timestamp, podName: line.podName, containerName: line.containerName, isMark: line.isMark)
                                }
                                logCounter = logLines.count
                                recentCount += sorted.count
                            }
                        }
                    } catch is CancellationError {
                        break
                    } catch {
                        retries += 1
                        guard !Task.isCancelled else { break }
                        try? await Task.sleep(for: .seconds(Double(retries) * 2))
                    }
                }
                await MainActor.run {
                    isLoadingInitial = false
                    streamTasks.removeValue(forKey: streamKey)
                    if streamTasks.isEmpty { isStreaming = false }
                }
            }
            streamTasks[streamKey] = task
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
        logCounter = 0
        isLoadingInitial = true
        startStreaming()
    }

    private func removePod(_ podName: String) {
        additionalPodNames.removeAll { $0 == podName }
        containerToggles.removeAll { $0.podName == podName }
        for (key, task) in streamTasks where key.hasPrefix(podName + "/") {
            task.cancel()
            streamTasks.removeValue(forKey: key)
        }
    }

    /// Fetches container info for a pod, adds toggles, then starts streaming
    private func addContainerTogglesAndStream(_ podName: String) {
        guard let client = viewModel.activeClients[resource.clusterId],
              let ns = resource.namespace else {
            // Fallback: stream without container info
            startStreamForPod(podName)
            return
        }
        Task {
            if let pod = try? await client.get(Pod.self, resourceType: .pods, name: podName, namespace: ns) {
                await MainActor.run {
                    for c in pod.spec?.initContainers ?? [] {
                        if !containerToggles.contains(where: { $0.id == "\(podName)/\(c.name)" }) {
                            containerToggles.append(ContainerToggle(id: "\(podName)/\(c.name)", podName: podName, containerName: c.name, enabled: false, isInit: true))
                        }
                    }
                    for c in pod.spec?.containers ?? [] {
                        if !containerToggles.contains(where: { $0.id == "\(podName)/\(c.name)" }) {
                            containerToggles.append(ContainerToggle(id: "\(podName)/\(c.name)", podName: podName, containerName: c.name, enabled: true, isInit: false))
                        }
                    }
                    // Now start streaming with proper container info
                    startStreamForPod(podName)
                }
            } else {
                // Couldn't fetch pod — stream all containers
                await MainActor.run { startStreamForPod(podName) }
            }
        }
    }

    // MARK: - Helpers

    private func colorForPod(_ podName: String) -> Color {
        guard let idx = allPodNames.firstIndex(of: podName) else { return .primary }
        return Self.podColors[idx % Self.podColors.count]
    }

    private func shortPodName(_ name: String) -> String {
        if name.count > 10 { return String(name.suffix(6)) }
        return name
    }

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

    private func exportLogs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "\(resource.name)-logs.log"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let lines = displayLines.filter { !$0.isMark }.map { line in
            var prefix = ""
            if timestampMode != .off {
                let fmt = timestampMode == .utc ? Self.utcFormatter : Self.localFormatter
                prefix += fmt.string(from: line.timestamp) + " "
            }
            if allPodNames.count > 1 { prefix += "\(line.podName)/\(line.containerName) | " }
            return prefix + line.text
        }
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private func openLogsInWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        let custom = ClusterCustomizationStore.shared.get(for: resource.clusterId)
        let connName = custom.displayName ?? viewModel.activeConnections.first?.name ?? "Cluster"
        window.title = "Logs — \(resource.name) (\(connName))"
        window.center()

        let logView = LogStreamView(resource: resource, isFullWindow: true)
            .environment(viewModel)
        window.contentView = NSHostingView(rootView: logView)
        window.makeKeyAndOrderFront(nil)

        // Prevent window from being deallocated
        LogWindowHolder.shared.hold(window)
    }

    private func findPod() -> Pod? {
        viewModel.pods[resource.clusterId]?.first { $0.name == resource.name }
    }
}

// Prevent log windows from being garbage collected
private class LogWindowHolder {
    static let shared = LogWindowHolder()
    private var windows: [NSWindow] = []

    func hold(_ window: NSWindow) {
        windows.append(window)
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] notif in
            self?.windows.removeAll { $0 === notif.object as? NSWindow }
        }
    }
}
