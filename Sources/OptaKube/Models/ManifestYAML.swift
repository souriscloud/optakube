import Foundation
import Yams

/// Converts a user-edited YAML manifest into the JSON body the API server expects.
///
/// Kubernetes parses manifests with JSON semantics (`sigs.k8s.io/yaml` round-trips YAML
/// through JSON), but Yams defaults to the YAML 1.1 scalar rules. Two of those rules
/// actively break manifest editing:
///
///   * `timestamp` — a bare `2026-01-01` or `2025-07-29T10:30:45Z` resolves to a
///     `Foundation.Date`. `JSONSerialization` cannot encode one, and it signals that by
///     raising `NSInvalidArgumentException` rather than throwing a Swift error, so a
///     surrounding `catch` cannot intercept it and the process aborts — losing whatever
///     the user had typed. Kubernetes treats these as strings.
///
///   * `bool` — YAML 1.1 resolves `yes`, `no`, `on`, and `off` to booleans. Kubernetes
///     does not; there, they are strings. Coercing them silently changed a value the
///     user wrote as text into `true`/`false` before it was sent, and the diff shown
///     for confirmation compares the *text*, so the change was invisible.
///
/// Integer and float rules are deliberately left alone: `0644` resolving to octal 420,
/// and `1.10` to `1.1`, is what `kubectl` does too, so matching it keeps the app
/// consistent with the tool users check their work against.
enum ManifestYAML {
    /// `Resolver.default` minus the two rules that disagree with Kubernetes.
    static let resolver: Resolver = {
        let withoutTimestamps = Resolver.default.removing(.timestamp)
        let jsonBooleans = "^(?:true|True|TRUE|false|False|FALSE)$"
        // `replacing` only throws if the pattern is not a valid regex; this one is a
        // literal, so the fallback is unreachable in practice.
        return (try? withoutTimestamps.replacing(.bool, with: jsonBooleans)) ?? withoutTimestamps
    }()

    enum ConversionError: LocalizedError {
        case empty
        case notRepresentable

        var errorDescription: String? {
            switch self {
            case .empty:
                return "The manifest is empty."
            case .notRepresentable:
                return "The manifest contains a value that can't be sent as JSON. "
                    + "Quote any date, time, or unusual scalar and try again."
            }
        }
    }

    /// Parses `yaml` with Kubernetes-compatible scalar semantics and encodes it as JSON.
    static func jsonData(from yaml: String) throws -> Data {
        guard let object = try Yams.load(yaml: yaml, resolver) else {
            throw ConversionError.empty
        }
        // Belt and braces: anything JSONSerialization would reject is caught here as a
        // Swift error instead of as an uncatchable ObjC exception.
        guard JSONSerialization.isValidJSONObject(object) else {
            throw ConversionError.notRepresentable
        }
        return try JSONSerialization.data(withJSONObject: object)
    }
}
