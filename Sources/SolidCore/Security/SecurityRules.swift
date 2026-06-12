import Foundation

/// Per-rule configuration override inside the `security.rules:` map.
public struct SecurityRuleOverride: Decodable, Equatable {
    public let severity: Severity?

    public init(severity: Severity? = nil) {
        self.severity = severity
    }
}

/// Opt-in security checks. Absent section = no checks (existing configs
/// unaffected). Each rule carries a built-in default severity; the global
/// `severity` overrides that, and a per-rule entry overrides both.
public struct SecurityRules: Decodable, Equatable {
    public let enabled: Bool
    /// Optional global override of every rule's built-in default severity.
    public let severity: Severity?
    /// IDs of rules to turn off entirely.
    public let disable: [String]
    /// Per-rule overrides keyed by rule ID.
    public let rules: [String: SecurityRuleOverride]

    public init(enabled: Bool, severity: Severity? = nil,
                disable: [String] = [], rules: [String: SecurityRuleOverride] = [:]) {
        self.enabled = enabled
        self.severity = severity
        self.disable = disable
        self.rules = rules
    }

    enum CodingKeys: String, CodingKey { case enabled, severity, disable, rules }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.enabled = (try? c.decode(Bool.self, forKey: .enabled)) ?? false
        self.severity = try? c.decode(Severity.self, forKey: .severity)
        self.disable = (try? c.decode([String].self, forKey: .disable)) ?? []
        self.rules = (try? c.decode([String: SecurityRuleOverride].self, forKey: .rules)) ?? [:]
    }

    /// per-rule override > global `severity` > the rule's built-in default.
    public func effectiveSeverity(ruleID: String, builtInDefault: Severity) -> Severity {
        rules[ruleID]?.severity ?? severity ?? builtInDefault
    }

    /// Returns whether the given rule is enabled (i.e. not in `disable`).
    /// NOTE: this intentionally does NOT check the master `enabled` flag —
    /// the engine guards on `enabled` separately before calling this method.
    public func isEnabled(ruleID: String) -> Bool {
        !disable.contains(ruleID)
    }
}

/// Central registry of every security rule.
public enum SecurityRuleRegistry {
    /// Every shipping rule. Grows task by task; the Info.plist ATS check is
    /// separate (not a SecurityRule — it reads plists, not Swift trees) but
    /// its ID `cleartextHTTP` is still registered for config validation.
    public static func makeAllRules() -> [any SecurityRule] {
        []   // rules are appended here as they land
    }

    public static var allRuleIDs: Set<String> {
        var ids = Set(makeAllRules().map { type(of: $0).id })
        ids.insert("cleartextHTTP")
        return ids
    }
}
