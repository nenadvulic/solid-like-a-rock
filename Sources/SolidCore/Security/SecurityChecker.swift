import Foundation
import SwiftParser
import SwiftSyntax

/// Runs every enabled security rule over a set of Swift files (single parse
/// per file, shared tree), resolving severities and filtering `solid:ignore`d
/// findings.
public struct SecurityChecker {
    private let config: SecurityRules
    private let rules: [any SecurityRule]

    /// `rules` is injectable for tests; production uses the full registry.
    public init(config: SecurityRules, rules: [any SecurityRule]? = nil) {
        self.config = config
        let all = rules ?? SecurityRuleRegistry.makeAllRules()
        self.rules = all.filter { config.isEnabled(ruleID: type(of: $0).id) }
    }

    /// Check already-collected Swift files (the list `Lint.run()` builds).
    public func check(swiftFiles: [String]) -> [Violation] {
        guard config.enabled, !rules.isEmpty else { return [] }
        var violations: [Violation] = []
        for file in swiftFiles {
            guard let source = try? String(contentsOfFile: file, encoding: .utf8) else { continue }
            let tree = Parser.parse(source: source)
            let converter = SourceLocationConverter(fileName: file, tree: tree)
            for rule in rules {
                let meta = type(of: rule)
                let severity = config.effectiveSeverity(ruleID: meta.id,
                                                        builtInDefault: meta.defaultSeverity)
                for finding in rule.check(tree, file: file, converter: converter) {
                    if let node = finding.node, hasSolidIgnore(node) { continue }
                    violations.append(.security(
                        ruleID: meta.id, category: meta.category, message: finding.message,
                        file: file, line: finding.line, severity: severity))
                }
            }
        }
        return violations
    }

    /// Full check: Swift rules over the collected files + the plist ATS check
    /// under the lint roots.
    public func check(swiftFiles: [String], roots: [String], excluding: [String]) -> [Violation] {
        guard config.enabled else { return [] }
        var violations = check(swiftFiles: swiftFiles)
        if config.isEnabled(ruleID: PlistATSCheck.id) {
            let severity = config.effectiveSeverity(ruleID: PlistATSCheck.id,
                                                    builtInDefault: PlistATSCheck.defaultSeverity)
            violations += PlistATSCheck(severity: severity).check(roots: roots, excluding: excluding)
        }
        return violations
    }
}
