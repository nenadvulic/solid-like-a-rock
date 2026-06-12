import SwiftSyntax

/// `privacy: .public` on a PII-named interpolation defeats os_log's redaction.
public struct PublicPIIInLogRule: SecurityRule {
    public static let id = "publicPIIInLog"
    public static let category = "Logging"
    public static let defaultSeverity = Severity.error

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
            override func visit(_ node: ExpressionSegmentSyntax) -> SyntaxVisitorContinueKind {
                let exprs = Array(node.expressions)
                guard exprs.count >= 2,
                      let privacyArg = exprs.first(where: { $0.label?.text == "privacy" }),
                      privacyArg.expression.trimmedDescription == ".public",
                      let value = exprs.first, value.label == nil
                else { return .visitChildren }
                // The interpolated expression's last identifier component:
                // `email` → email; `session.authToken` → authToken.
                let name = value.expression.as(MemberAccessExprSyntax.self)?.declName.baseName.text
                    ?? value.expression.trimmedDescription
                if matchesSensitiveName(name, words: piiNameWords) {
                    findings.append(SecurityFinding(
                        line: node.startLocation(converter: converter).line,
                        message: "'\(name)' is logged with privacy: .public — os_log redaction is defeated for PII",
                        node: Syntax(node)))
                }
                return .visitChildren
            }
        }
        let v = V(converter: converter)
        v.walk(tree)
        return v.findings
    }
}
