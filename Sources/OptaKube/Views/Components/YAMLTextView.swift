import SwiftUI
import AppKit

/// A YAML-aware text view backed by `NSTextView` — the one editor/reader used
/// everywhere YAML is shown. It gives:
///   • live syntax highlighting (via `YAMLHighlighter`)
///   • YAML-aware editing: Return keeps the current indent (and adds one level
///     after a `key:` or block scalar `|`/`>`), Tab inserts two spaces, Shift-Tab
///     dedents two spaces
///   • **all macOS text substitutions disabled** — smart quotes, smart dashes,
///     and text replacement silently corrupt YAML, so they must be off
///
/// Set `isEditable: false` for read-only displays (still highlighted, still
/// natively selectable); pass a constant binding in that case.
struct YAMLTextView: NSViewRepresentable {
    @Binding var text: String
    var isEditable: Bool = true

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        guard let textView = scroll.documentView as? NSTextView else { return scroll }

        let font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.font = font
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.delegate = context.coordinator
        textView.textContainerInset = NSSize(width: 6, height: 8)

        // Critical for YAML: never let macOS "improve" the text.
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false

        textView.backgroundColor = .textBackgroundColor
        textView.drawsBackground = true
        textView.insertionPointColor = .labelColor
        scroll.drawsBackground = false

        context.coordinator.apply(text, to: textView)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView else { return }
        textView.isEditable = isEditable
        // Only rewrite when the external value diverges (e.g. reset on edit start,
        // programmatic load) — never while the user is mid-keystroke, which would
        // fight the cursor.
        if textView.string != text {
            context.coordinator.apply(text, to: textView)
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        private let parent: YAMLTextView
        /// Guards against the re-highlight write-back looping through textDidChange.
        private var isApplying = false

        init(_ parent: YAMLTextView) { self.parent = parent }

        /// Replace contents and re-highlight, preserving the selection.
        func apply(_ string: String, to textView: NSTextView) {
            isApplying = true
            let sel = textView.selectedRanges
            textView.textStorage?.setAttributedString(
                YAMLHighlighter.nsAttributed(string, font: monoFont(textView)))
            textView.selectedRanges = sel
            isApplying = false
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView, !isApplying else { return }
            let value = textView.string
            parent.text = value
            // Re-highlight in place, keeping the caret put.
            isApplying = true
            let sel = textView.selectedRanges
            let font = monoFont(textView)
            textView.textStorage?.setAttributedString(YAMLHighlighter.nsAttributed(value, font: font))
            textView.selectedRanges = sel
            isApplying = false
        }

        /// YAML-aware key handling for Return / Tab / Shift-Tab.
        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                return insertNewlineKeepingIndent(textView)
            case #selector(NSResponder.insertTab(_:)):
                textView.insertText("  ", replacementRange: textView.selectedRange())
                return true
            case #selector(NSResponder.insertBacktab(_:)):
                return dedent(textView)
            default:
                return false
            }
        }

        // MARK: helpers

        private func monoFont(_ textView: NSTextView) -> NSFont {
            textView.font ?? .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        }

        private func insertNewlineKeepingIndent(_ textView: NSTextView) -> Bool {
            let ns = textView.string as NSString
            let sel = textView.selectedRange()
            let lineRange = ns.lineRange(for: NSRange(location: sel.location, length: 0))
            // Text on the current line up to the caret.
            let upToCaret = ns.substring(with: NSRange(location: lineRange.location,
                                                       length: max(0, sel.location - lineRange.location)))
            let leading = String(upToCaret.prefix { $0 == " " })
            var indent = leading
            let trimmed = upToCaret.trimmingCharacters(in: .whitespaces)
            // One extra level after a mapping key with no inline value, or a block
            // scalar introducer.
            if trimmed.hasSuffix(":") || trimmed.hasSuffix("|") || trimmed.hasSuffix(">") {
                indent += "  "
            }
            textView.insertText("\n" + indent, replacementRange: sel)
            return true
        }

        private func dedent(_ textView: NSTextView) -> Bool {
            let ns = textView.string as NSString
            let sel = textView.selectedRange()
            let lineRange = ns.lineRange(for: NSRange(location: sel.location, length: 0))
            let line = ns.substring(with: lineRange)
            let leadingSpaces = line.prefix { $0 == " " }.count
            guard leadingSpaces > 0 else { return true }
            let remove = min(2, leadingSpaces)
            let removeRange = NSRange(location: lineRange.location, length: remove)
            if textView.shouldChangeText(in: removeRange, replacementString: "") {
                textView.textStorage?.replaceCharacters(in: removeRange, with: "")
                textView.didChangeText()
            }
            return true
        }
    }
}
