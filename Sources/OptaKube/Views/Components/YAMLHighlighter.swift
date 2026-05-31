import SwiftUI
import AppKit

/// Single source of truth for YAML syntax highlighting across the app — used by
/// the read-only displays (SwiftUI `AttributedString`) and the editable
/// `YAMLTextView` (`NSAttributedString` over an `NSTextView`). One line-based
/// tokenizer feeds both so colours stay identical everywhere YAML appears.
enum YAMLHighlighter {

    /// Semantic token classes. Mapped to concrete colours below so the palette
    /// lives in exactly one place.
    enum TokenColor {
        case key, string, number, keyword, comment, punctuation, plain, docMarker
    }

    static func nsColor(_ c: TokenColor) -> NSColor {
        switch c {
        case .key:         return .systemTeal
        case .string:      return .systemGreen
        case .number:      return .systemOrange
        case .keyword:     return .systemPurple
        case .comment:     return .systemGray
        case .punctuation: return .secondaryLabelColor
        case .plain:       return .labelColor
        case .docMarker:   return .systemBlue
        }
    }

    // MARK: - Builders

    /// SwiftUI attributed string for read-only `Text` displays.
    static func attributedString(_ yaml: String, pointSize: CGFloat = NSFont.systemFontSize) -> AttributedString {
        let mono = Font.system(size: pointSize, design: .monospaced)
        var result = AttributedString()
        let lines = yaml.components(separatedBy: "\n")
        for (i, line) in lines.enumerated() {
            if i > 0 {
                var nl = AttributedString("\n"); nl.font = mono; result.append(nl)
            }
            for (text, color) in tokens(forLine: line) {
                var run = AttributedString(text)
                run.font = mono
                run.foregroundColor = Color(nsColor: nsColor(color))
                result.append(run)
            }
        }
        return result
    }

    /// AppKit attributed string for the editable text view. Applies colour over a
    /// fixed monospaced font.
    static func nsAttributed(_ yaml: String, font: NSFont) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let lines = yaml.components(separatedBy: "\n")
        for (i, line) in lines.enumerated() {
            if i > 0 { result.append(NSAttributedString(string: "\n", attributes: [.font: font])) }
            for (text, color) in tokens(forLine: line) {
                result.append(NSAttributedString(string: text, attributes: [
                    .font: font,
                    .foregroundColor: nsColor(color),
                ]))
            }
        }
        return result
    }

    // MARK: - Tokenizer (line-based)

    /// Splits one line into coloured runs whose concatenation is exactly the line.
    static func tokens(forLine raw: String) -> [(String, TokenColor)] {
        // Leading indentation, kept as a neutral run so columns line up.
        let indentCount = raw.prefix { $0 == " " || $0 == "\t" }.count
        let indent = String(raw.prefix(indentCount))
        var rest = String(raw.dropFirst(indentCount))
        var out: [(String, TokenColor)] = []
        if !indent.isEmpty { out.append((indent, .plain)) }
        if rest.isEmpty { return out }

        // Whole-line comment.
        if rest.hasPrefix("#") { out.append((rest, .comment)); return out }
        // Document markers.
        if rest == "---" || rest == "..." { out.append((rest, .docMarker)); return out }

        // Sequence dashes, possibly nested ("- - item").
        while rest.hasPrefix("- ") || rest == "-" {
            if rest == "-" { out.append(("-", .punctuation)); return out }
            out.append(("- ", .punctuation))
            rest = String(rest.dropFirst(2))
        }
        if rest.isEmpty { return out }

        out.append(contentsOf: keyValueTokens(rest))
        return out
    }

    private static func keyValueTokens(_ s: String) -> [(String, TokenColor)] {
        if let colon = keyColonIndex(s) {
            let key = String(s[...colon])            // includes the trailing ':'
            var toks: [(String, TokenColor)] = [(key, .key)]
            let after = String(s[s.index(after: colon)...])
            if after.isEmpty { return toks }
            let spaces = after.prefix { $0 == " " }
            if !spaces.isEmpty { toks.append((String(spaces), .plain)) }
            let value = String(after.dropFirst(spaces.count))
            if value.isEmpty { return toks }
            if value.hasPrefix("#") { toks.append((value, .comment)); return toks }
            toks.append((value, scalarColor(value)))
            return toks
        }
        // No key delimiter → a bare scalar (e.g. a list-item value or block line).
        return [(s, scalarColor(s))]
    }

    /// Index of the ':' that separates a mapping key from its value — i.e. a colon
    /// followed by a space or end-of-line. Returns nil for quoted scalars and for
    /// colons inside values (so `http://x` and `time: "10:30"` don't mis-split).
    private static func keyColonIndex(_ s: String) -> String.Index? {
        if s.hasPrefix("\"") || s.hasPrefix("'") { return nil }
        var i = s.startIndex
        while i < s.endIndex {
            if s[i] == ":" {
                let next = s.index(after: i)
                if next == s.endIndex || s[next] == " " { return i }
            }
            i = s.index(after: i)
        }
        return nil
    }

    private static func scalarColor(_ value: String) -> TokenColor {
        let v = value.trimmingCharacters(in: .whitespaces)
        if v.hasPrefix("\"") || v.hasPrefix("'") { return .string }
        if v.hasPrefix("&") || v.hasPrefix("*") || v.hasPrefix("|") || v.hasPrefix(">") { return .punctuation }
        switch v.lowercased() {
        case "true", "false", "null", "~", "yes", "no", "on", "off": return .keyword
        default: break
        }
        if Double(v) != nil { return .number }
        return .string
    }
}
