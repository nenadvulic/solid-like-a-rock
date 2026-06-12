import SwiftSyntax

/// A URLSession auth-challenge delegate that hands `.useCredential` a
/// credential built from the server trust WITHOUT any SecTrustEvaluate* call
/// accepts ANY certificate — TLS validation is effectively off.
public struct DisabledTLSValidationRule: SecurityRule {
    public static let id = "disabledTLSValidation"
    public static let category = "Network"
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
            override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
                guard node.name.text == "urlSession",
                      node.signature.parameterClause.parameters.contains(where: {
                          $0.firstName.text == "didReceive"
                      }),
                      let body = node.body else { return .visitChildren }
                let text = body.trimmedDescription
                guard text.contains(".useCredential"),
                      text.contains("URLCredential(trust:"),
                      !text.contains("SecTrustEvaluate") else { return .visitChildren }
                // Report at the completionHandler call line, not the func line.
                final class CallFinder: SyntaxVisitor {
                    var node: FunctionCallExprSyntax?
                    override func visit(_ call: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
                        if node == nil, call.trimmedDescription.contains(".useCredential") {
                            node = call
                        }
                        return .visitChildren
                    }
                }
                let finder = CallFinder(viewMode: .sourceAccurate)
                finder.walk(body)
                let target = finder.node.map(Syntax.init) ?? Syntax(node)
                findings.append(SecurityFinding(
                    line: target.startLocation(converter: converter).line,
                    message: "auth-challenge handler accepts the server trust without SecTrustEvaluate — TLS validation is disabled (any certificate is trusted)",
                    node: target))
                return .visitChildren
            }
        }
        let v = V(converter: converter)
        v.walk(tree)
        return v.findings
    }
}
