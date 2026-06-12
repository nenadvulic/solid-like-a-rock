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

                // Use token text only — trivia (comments) are excluded, so a
                // commented-out SecTrustEvaluate cannot suppress the finding.
                let tokens = body.tokens(viewMode: .sourceAccurate).map(\.text)
                let text = tokens.joined(separator: " ")

                // ".useCredential" tokens: `. useCredential`; match on the identifier.
                guard text.contains("useCredential"),
                      // "URLCredential(trust:" tokens: `URLCredential ( trust :`
                      text.contains("URLCredential ( trust") else { return .visitChildren }

                // Cancel branch: if the handler CAN reject the challenge
                // (cancelAuthenticationChallenge present as a token), some
                // validation logic exists — under-report direction; skip.
                // Trade-off: a trust-all that also has a decorative cancel path
                // would be missed, but provability wins over sensitivity here.
                if tokens.contains("cancelAuthenticationChallenge") { return .visitChildren }

                // No SecTrustEvaluate* token means no system trust evaluation.
                // Match any token that starts with "SecTrustEvaluate" to cover
                // SecTrustEvaluate, SecTrustEvaluateWithError, SecTrustEvaluateAsync…
                let hasTrustEval = tokens.contains(where: { $0.hasPrefix("SecTrustEvaluate") })
                guard !hasTrustEval else { return .visitChildren }

                // Report at the completionHandler call line, not the func line.
                // CallFinder works on node descriptions (trivia-inclusive) — fine
                // for line attribution; we only changed how we detect the pattern.
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
