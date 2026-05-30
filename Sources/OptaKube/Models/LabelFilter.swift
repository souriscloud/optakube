import Foundation

/// A parsed Kubernetes label selector. Supports the common equality- and set-based
/// requirements that `kubectl get -l` accepts:
///
///   - `key=value` / `key==value`  — equality
///   - `key!=value`                — inequality
///   - `key`                       — existence
///   - `!key`                      — non-existence
///   - `key in (a, b, c)`          — value is one of
///   - `key notin (a, b, c)`       — value is none of
///
/// Multiple comma-separated requirements are ANDed together, mirroring kubectl. A
/// resource matches only if every requirement holds. An empty or whitespace-only
/// selector matches everything (so the filter is a no-op until the user types).
///
/// Parsing is forgiving: a malformed requirement is dropped rather than failing the
/// whole selector, so a half-typed filter never hides every row at once. `isValid`
/// reports whether the *entire* string parsed cleanly, for UI affordances.
///
/// Named `LabelFilter` to avoid colliding with the K8s `LabelSelector` model
/// (`matchLabels`) used by Deployments, NetworkPolicies, etc.
struct LabelFilter {
    enum Requirement: Equatable {
        case equals(key: String, value: String)
        case notEquals(key: String, value: String)
        case exists(key: String)
        case notExists(key: String)
        case inSet(key: String, values: Set<String>)
        case notInSet(key: String, values: Set<String>)
    }

    let requirements: [Requirement]
    /// True when every comma-separated clause parsed into a requirement.
    let isValid: Bool

    /// An empty selector — matches everything.
    static let empty = LabelFilter(requirements: [], isValid: true)

    init(requirements: [Requirement], isValid: Bool) {
        self.requirements = requirements
        self.isValid = isValid
    }

    /// Parse a selector string. Never throws; unparseable clauses are skipped and
    /// reflected in `isValid`.
    init(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            self = .empty
            return
        }

        var parsed: [Requirement] = []
        var allValid = true
        for clause in Self.splitTopLevel(trimmed) {
            let piece = clause.trimmingCharacters(in: .whitespaces)
            if piece.isEmpty { continue }
            if let req = Self.parseClause(piece) {
                parsed.append(req)
            } else {
                allValid = false
            }
        }
        self.requirements = parsed
        self.isValid = allValid
    }

    /// Split on commas that are not inside `( … )`, so `env in (a,b),app=x` becomes
    /// two clauses rather than three.
    private static func splitTopLevel(_ s: String) -> [String] {
        var result: [String] = []
        var depth = 0
        var current = ""
        for ch in s {
            switch ch {
            case "(": depth += 1; current.append(ch)
            case ")": depth = max(0, depth - 1); current.append(ch)
            case "," where depth == 0:
                result.append(current); current = ""
            default:
                current.append(ch)
            }
        }
        result.append(current)
        return result
    }

    private static func parseClause(_ clause: String) -> Requirement? {
        // Set-based: "key in (a, b)" / "key notin (a, b)"
        if let openParen = clause.firstIndex(of: "("), clause.hasSuffix(")") {
            let head = clause[clause.startIndex..<openParen].trimmingCharacters(in: .whitespaces)
            let inner = clause[clause.index(after: openParen)..<clause.index(before: clause.endIndex)]
            let values = Set(inner.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
            if head.hasSuffix(" notin") {
                let key = String(head.dropLast(" notin".count)).trimmingCharacters(in: .whitespaces)
                guard isValidKey(key) else { return nil }
                return .notInSet(key: key, values: values)
            }
            if head.hasSuffix(" in") {
                let key = String(head.dropLast(" in".count)).trimmingCharacters(in: .whitespaces)
                guard isValidKey(key) else { return nil }
                return .inSet(key: key, values: values)
            }
            return nil
        }

        // Inequality: "key!=value"
        if let r = clause.range(of: "!=") {
            let key = String(clause[clause.startIndex..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
            let value = String(clause[r.upperBound...]).trimmingCharacters(in: .whitespaces)
            guard isValidKey(key) else { return nil }
            return .notEquals(key: key, value: value)
        }

        // Equality: "key==value" or "key=value" (check == before = so we don't split it)
        if let r = clause.range(of: "==") ?? clause.range(of: "=") {
            let key = String(clause[clause.startIndex..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
            let value = String(clause[r.upperBound...]).trimmingCharacters(in: .whitespaces)
            guard isValidKey(key) else { return nil }
            return .equals(key: key, value: value)
        }

        // Non-existence: "!key"
        if clause.hasPrefix("!") {
            let key = String(clause.dropFirst()).trimmingCharacters(in: .whitespaces)
            guard isValidKey(key) else { return nil }
            return .notExists(key: key)
        }

        // Existence: bare "key"
        guard isValidKey(clause) else { return nil }
        return .exists(key: clause)
    }

    /// A label key can't be empty or contain selector operators. Kept deliberately
    /// loose otherwise — we trust the cluster to reject genuinely invalid keys.
    private static func isValidKey(_ key: String) -> Bool {
        !key.isEmpty && !key.contains("=") && !key.contains("(") && !key.contains(")")
    }

    /// Does a resource's label set satisfy every requirement?
    func matches(_ labels: [String: String]?) -> Bool {
        guard !requirements.isEmpty else { return true }
        let labels = labels ?? [:]
        for req in requirements {
            switch req {
            case .equals(let k, let v):
                if labels[k] != v { return false }
            case .notEquals(let k, let v):
                // kubectl semantics: key absent also satisfies key!=value
                if labels[k] == v { return false }
            case .exists(let k):
                if labels[k] == nil { return false }
            case .notExists(let k):
                if labels[k] != nil { return false }
            case .inSet(let k, let vs):
                guard let val = labels[k], vs.contains(val) else { return false }
            case .notInSet(let k, let vs):
                if let val = labels[k], vs.contains(val) { return false }
            }
        }
        return true
    }
}
