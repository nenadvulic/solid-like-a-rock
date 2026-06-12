import SwiftSyntax

/// `canEvaluatePolicy(_, error: nil)` throws away the only signal explaining
/// WHY biometrics are unavailable (lockout, not enrolled, …).
public struct BiometryNoErrorHandlingRule: SecurityRule {
    public static let id = "biometryNoErrorHandling"
    public static let category = "Auth"
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
            override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
                guard let member = node.calledExpression.as(MemberAccessExprSyntax.self),
                      member.declName.baseName.text == "canEvaluatePolicy",
                      let errorArg = node.arguments.first(where: { $0.label?.text == "error" }),
                      errorArg.expression.is(NilLiteralExprSyntax.self)
                else { return .visitChildren }
                findings.append(SecurityFinding(
                    line: node.startLocation(converter: converter).line,
                    message: "canEvaluatePolicy(_, error: nil) discards the failure reason — pass &error and handle lockout / not-enrolled cases",
                    node: Syntax(node)))
                return .visitChildren
            }
        }
        let v = V(converter: converter)
        v.walk(tree)
        return v.findings
    }
}
