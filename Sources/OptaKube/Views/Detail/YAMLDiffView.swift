import SwiftUI

/// A line-level unified diff between the resource's current manifest and the user's
/// edits, shown as a confirmation step before a YAML apply. Built on Swift's
/// `CollectionDifference` so we don't hand-roll an LCS — the only work here is
/// merging removals and insertions back into a readable unified ordering.
struct YAMLDiffView: View {
    let current: String
    let edited: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    private var lines: [DiffLine] { Self.unifiedDiff(from: current, to: edited) }

    private var changeCount: (added: Int, removed: Int) {
        lines.reduce(into: (0, 0)) { acc, line in
            switch line.kind {
            case .added: acc.0 += 1
            case .removed: acc.1 += 1
            case .context: break
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.title2)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Review changes")
                        .font(.headline)
                    let c = changeCount
                    Text("\(c.added) added · \(c.removed) removed — applied with PUT")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding()

            Divider()

            if changeCount.added == 0 && changeCount.removed == 0 {
                ContentUnavailableView("No changes", systemImage: "checkmark.circle")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(lines) { line in
                            diffRow(line)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }
            }

            Divider()

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button("Apply") { onConfirm() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(changeCount.added == 0 && changeCount.removed == 0)
            }
            .padding()
        }
        .frame(minWidth: 560, minHeight: 420)
    }

    @ViewBuilder
    private func diffRow(_ line: DiffLine) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(line.kind.sigil)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(line.kind.foreground)
                .frame(width: 12)
            Text(line.text.isEmpty ? " " : line.text)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(line.kind == .context ? .secondary : line.kind.foreground)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 1)
        .background(line.kind.background)
    }

    // MARK: - Diff model

    struct DiffLine: Identifiable {
        enum Kind: Equatable {
            case context, added, removed
            var sigil: String { self == .added ? "+" : self == .removed ? "-" : " " }
            var foreground: Color { self == .added ? .green : self == .removed ? .red : .primary }
            var background: Color {
                switch self {
                case .added: return .green.opacity(0.10)
                case .removed: return .red.opacity(0.10)
                case .context: return .clear
                }
            }
        }
        let id = UUID()
        let kind: Kind
        let text: String
    }

    /// Merge a `CollectionDifference` back into unified order: removed source lines
    /// appear immediately before the unchanged line they preceded, insertions appear at
    /// their destination offset.
    static func unifiedDiff(from current: String, to edited: String) -> [DiffLine] {
        let src = current.components(separatedBy: "\n")
        let dst = edited.components(separatedBy: "\n")
        let diff = dst.difference(from: src)

        var removeOffsets = Set<Int>()
        var insertOffsets = Set<Int>()
        for change in diff {
            switch change {
            case .remove(let offset, _, _): removeOffsets.insert(offset)
            case .insert(let offset, _, _): insertOffsets.insert(offset)
            }
        }

        var result: [DiffLine] = []
        var i = 0  // index into src
        for j in 0..<dst.count {
            if insertOffsets.contains(j) {
                result.append(DiffLine(kind: .added, text: dst[j]))
                continue
            }
            // Unchanged destination line — first flush any removed source lines before it.
            while i < src.count && removeOffsets.contains(i) {
                result.append(DiffLine(kind: .removed, text: src[i]))
                i += 1
            }
            if i < src.count {
                result.append(DiffLine(kind: .context, text: src[i]))
                i += 1
            }
        }
        // Trailing removals.
        while i < src.count {
            if removeOffsets.contains(i) {
                result.append(DiffLine(kind: .removed, text: src[i]))
            }
            i += 1
        }
        return result
    }
}
