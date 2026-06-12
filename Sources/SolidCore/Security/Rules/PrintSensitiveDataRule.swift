import SwiftSyntax

/// print/NSLog/debugPrint/dump ship to the console in release builds and end
/// up in sysdiagnoses; a sensitive identifier there is a leak. Warning —
/// name-based heuristic.
public struct PrintSensitiveDataRule: SecurityRule {
    public static let id = "printSensitiveData"
    public static let category = "Logging"
    public static let defaultSeverity = Severity.warning

    static let sinkNames: Set<String> = ["print", "debugPrint", "NSLog", "dump"]

    /// PII + secret words combined: both leak in a log line.
    ///
    /// Bare "key" is intentionally excluded: `keyWindow`, `keyPath`, and
    /// dict-loop variables named `key` are ubiquitous Swift idioms that carry
    /// no secret; they outnumber the true-positive `forKey:` pattern by a wide
    /// margin. Multiword forms (`apikey`, `apiKey`, `storeKey`) still fire
    /// because `matchesSensitiveName` joins adjacent camel/snake words.
    ///
    /// Bare "token" is retained: `tokens.count`/`token.kind` false-positives
    /// are silenced by the "last-component-only" evaluation (change #1), while
    /// `authToken`, `sessionToken`, and a bare `token` variable being printed
    /// remain true positives worth warning about.
    static let words: [String] = {
        let base = Array(Set(piiNameWords + secretNameWords))
        // Remove the standalone word "key" — see rationale above.
        return base.filter { $0 != "key" }
    }()

    public init() {}

    public func check(_ tree: SourceFileSyntax, file: String,
                      converter: SourceLocationConverter) -> [SecurityFinding] {
        final class V: SyntaxVisitor {
            var findings: [SecurityFinding] = []
            let converter: SourceLocationConverter
            init(converter: SourceLocationConverter) {
                self.converter = converter
                super.init(viewMode: .sourceAccurate)
            }
            override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
                guard let callee = node.calledExpression.as(DeclReferenceExprSyntax.self),
                      PrintSensitiveDataRule.sinkNames.contains(callee.baseName.text)
                else { return .visitChildren }
                if let name = Self.firstSensitiveIdentifier(in: node) {
                    findings.append(SecurityFinding(
                        line: node.startLocation(converter: converter).line,
                        message: "'\(name)' is written to the console via \(callee.baseName.text)() — remove it or use os_log with privacy redaction",
                        node: Syntax(node)))
                }
                return .visitChildren
            }

            /// Returns the first sensitive name that is actually printed.
            ///
            /// "What is actually printed" means:
            ///   - For a bare identifier (`DeclReferenceExprSyntax`): its name.
            ///   - For a member-access expression (`a.b`): only the last
            ///     component (`b`) — the base `a` is the object, not the value.
            ///   - For a string literal: recurse into every interpolation
            ///     segment and apply the same two rules to each interpolated
            ///     expression. Static string content never triggers.
            ///   - Anything else (array literals, function calls, …): ignored.
            ///
            /// This mirrors `PublicPIIInLogRule`'s last-component approach and
            /// prevents bases of member accesses (`tokens` in `tokens.count`,
            /// `token` in `token.kind`) from producing false positives.
            static func firstSensitiveIdentifier(in call: FunctionCallExprSyntax) -> String? {
                for arg in call.arguments {
                    if let name = sensitiveName(in: arg.expression) { return name }
                }
                return nil
            }

            /// Evaluate a single expression for what name it actually prints.
            static func sensitiveName(in expr: ExprSyntax) -> String? {
                // Member access: only the last component matters.
                if let member = expr.as(MemberAccessExprSyntax.self) {
                    let name = member.declName.baseName.text
                    if matchesSensitiveName(name, words: PrintSensitiveDataRule.words) { return name }
                    return nil
                }
                // Bare identifier: its own name.
                if let ref = expr.as(DeclReferenceExprSyntax.self) {
                    let name = ref.baseName.text
                    if matchesSensitiveName(name, words: PrintSensitiveDataRule.words) { return name }
                    return nil
                }
                // String literal: recurse into interpolation segments only.
                if let str = expr.as(StringLiteralExprSyntax.self) {
                    for segment in str.segments {
                        guard let interp = segment.as(ExpressionSegmentSyntax.self) else { continue }
                        for labeledExpr in interp.expressions {
                            if let name = sensitiveName(in: labeledExpr.expression) { return name }
                        }
                    }
                    return nil
                }
                return nil
            }
        }
        let v = V(converter: converter)
        v.walk(tree)
        return v.findings
    }
}
