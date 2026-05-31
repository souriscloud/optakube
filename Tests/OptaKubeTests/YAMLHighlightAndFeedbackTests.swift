import XCTest
@testable import OptaKube

final class YAMLHighlightAndFeedbackTests: XCTestCase {

    // MARK: - YAML tokenizer

    /// Tokens must always reconstruct the original line exactly (no dropped or
    /// duplicated characters) — the highlighter must never alter the text.
    func testTokensReconstructLineLosslessly() {
        let lines = [
            "apiVersion: apps/v1",
            "  name: checkout-api",
            "    - containerPort: 8080",
            "# a comment",
            "---",
            "      image: ghcr.io/acme/api:v1.4.2",
            "    enabled: true",
            "replicas: 3",
            "",
            "        ",
            "url: http://example.com:8080/path",
        ]
        for line in lines {
            let joined = YAMLHighlighter.tokens(forLine: line).map(\.0).joined()
            XCTAssertEqual(joined, line, "tokens did not reconstruct: \(line)")
        }
    }

    func testKeyAndScalarColors() {
        // key before the colon
        let kv = YAMLHighlighter.tokens(forLine: "replicas: 3")
        XCTAssertEqual(kv.first?.0, "replicas:")
        XCTAssertEqual(kv.first?.1, .key)
        // numeric value
        XCTAssertEqual(kv.last?.0, "3")
        XCTAssertEqual(kv.last?.1, .number)

        // boolean keyword
        XCTAssertEqual(YAMLHighlighter.tokens(forLine: "enabled: true").last?.1, .keyword)
        XCTAssertEqual(YAMLHighlighter.tokens(forLine: "value: null").last?.1, .keyword)
        // quoted string
        XCTAssertEqual(YAMLHighlighter.tokens(forLine: "msg: \"hi\"").last?.1, .string)
    }

    func testCommentAndDocMarker() {
        XCTAssertEqual(YAMLHighlighter.tokens(forLine: "# hello").first?.1, .comment)
        XCTAssertEqual(YAMLHighlighter.tokens(forLine: "  # indented").last?.1, .comment)
        XCTAssertEqual(YAMLHighlighter.tokens(forLine: "---").first?.1, .docMarker)
    }

    func testListDashIsPunctuationAndValueColored() {
        let toks = YAMLHighlighter.tokens(forLine: "  - name: web")
        // leading indent + dash + key + value
        XCTAssertTrue(toks.contains { $0.0 == "- " && $0.1 == .punctuation })
        XCTAssertTrue(toks.contains { $0.0 == "name:" && $0.1 == .key })
    }

    /// A URL value has colons but no `: ` key delimiter after the key — the value
    /// must stay intact, not be split at `http:`.
    func testURLValueNotMisSplit() {
        let toks = YAMLHighlighter.tokens(forLine: "url: http://example.com:8080")
        XCTAssertEqual(toks.first?.0, "url:")
        XCTAssertTrue(toks.contains { $0.0 == "http://example.com:8080" })
    }

    func testAttributedStringRoundTripsPlainText() {
        let yaml = "apiVersion: v1\nkind: ConfigMap\ndata:\n  k: v"
        // The visible characters of the attributed string equal the input.
        let attr = YAMLHighlighter.attributedString(yaml)
        XCTAssertEqual(String(attr.characters), yaml)
    }

    // MARK: - GitHub feedback URL

    func testIssueURLHasPrefixedTitleBodyAndLabel() {
        let url = GitHubFeedback.issueURL(kind: .bug, title: "crash on connect",
                                          body: "steps here", includeDiagnostics: false)
        let s = url!.absoluteString
        XCTAssertTrue(s.hasPrefix("https://github.com/souriscloud/optakube/issues/new"))
        let comps = URLComponents(url: url!, resolvingAgainstBaseURL: false)!
        let items = Dictionary(uniqueKeysWithValues: comps.queryItems!.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(items["title"], "[Bug] crash on connect")
        XCTAssertEqual(items["labels"], "bug")
        XCTAssertEqual(items["body"], "steps here")
    }

    func testDiagnosticsAppendedWhenRequested() {
        let text = GitHubFeedback.reportText(body: "x", includeDiagnostics: true)
        XCTAssertTrue(text.contains("OptaKube"))
        XCTAssertTrue(text.contains("macOS"))
        // and omitted when not requested
        XCTAssertEqual(GitHubFeedback.reportText(body: "x", includeDiagnostics: false), "x")
    }

    func testFeatureAndQuestionLabels() {
        XCTAssertEqual(FeedbackKind.feature.githubLabel, "enhancement")
        XCTAssertEqual(FeedbackKind.feature.titlePrefix, "[Feature] ")
        XCTAssertEqual(FeedbackKind.question.githubLabel, "question")
    }
}
