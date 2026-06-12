import SwiftSyntax

/// Find `….set(_, forKey: "literal")` / `….setValue(_, forKey: "literal")`
/// calls on a UserDefaults-looking base (`UserDefaults.standard`, `defaults`,
/// …) whose key matches `words` but none of `excludeWords` (lets the PII rule
/// defer whole keys to the credential rule). Conservative: non-literal keys
/// never match, and a Bool/Int literal value is provably not a secret
/// (preference flags like `defaults.set(true, forKey: "biometricAuthEnabled")`
/// stay silent).
func userDefaultsSetFindings(in tree: SourceFileSyntax,
                             converter: SourceLocationConverter,
                             words: [String],
                             excludeWords: [String] = [],
                             message: @escaping (String) -> String) -> [SecurityFinding] {
    final class V: SyntaxVisitor {
        var findings: [SecurityFinding] = []
        let converter: SourceLocationConverter
        let words: [String]
        let excludeWords: [String]
        let message: (String) -> String
        init(converter: SourceLocationConverter, words: [String], excludeWords: [String],
             message: @escaping (String) -> String) {
            self.converter = converter
            self.words = words
            self.excludeWords = excludeWords
            self.message = message
            super.init(viewMode: .sourceAccurate)
        }
        override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
            guard let member = node.calledExpression.as(MemberAccessExprSyntax.self),
                  ["set", "setValue"].contains(member.declName.baseName.text),
                  Self.baseLooksLikeUserDefaults(member.base),
                  let keyArg = node.arguments.first(where: { $0.label?.text == "forKey" }),
                  let literal = keyArg.expression.as(StringLiteralExprSyntax.self),
                  let key = plainTextValue(of: literal),
                  matchesSensitiveName(key, words: words),
                  !matchesSensitiveName(key, words: excludeWords),
                  !Self.valueIsProvablyNotSecret(node)
            else { return .visitChildren }
            findings.append(SecurityFinding(
                line: node.startLocation(converter: converter).line,
                message: message(key), node: Syntax(node)))
            return .visitChildren
        }
        /// The stored VALUE (first unlabeled argument) is a Bool or Int
        /// literal — provably not a credential or PII, whatever the key says.
        static func valueIsProvablyNotSecret(_ node: FunctionCallExprSyntax) -> Bool {
            guard let value = node.arguments.first(where: { $0.label == nil })?.expression
            else { return false }
            return value.is(BooleanLiteralExprSyntax.self) || value.is(IntegerLiteralExprSyntax.self)
        }
        static func baseLooksLikeUserDefaults(_ base: ExprSyntax?) -> Bool {
            guard let text = base?.trimmedDescription.lowercased() else { return false }
            // "defaults" also covers "userdefaults" (substring), so a single
            // check suffices for UserDefaults.standard and custom wrappers alike.
            return text.contains("defaults")
        }
    }
    let v = V(converter: converter, words: words, excludeWords: excludeWords, message: message)
    v.walk(tree)
    return v.findings
}

/// The literal's plain text, or nil when it contains interpolation
/// (an interpolated string is not a hardcoded constant).
func plainTextValue(of literal: StringLiteralExprSyntax) -> String? {
    var out = ""
    for segment in literal.segments {
        guard let s = segment.as(StringSegmentSyntax.self) else { return nil }
        out += s.content.text
    }
    return out
}

/// Strip `as` casts from an expression: `x as T`, `x as T as U` → `x`.
///
/// SwiftSyntax 600.x parses `x as T` not as AsExprSyntax but as a flat
/// SequenceExprSyntax with three elements — [expr, UnresolvedAsExprSyntax,
/// typeExpr]. This helper recognizes that shape, recurses through nested
/// casts, and returns the expression unchanged when there is no cast.
func stripAsCasts(_ expr: ExprSyntax) -> ExprSyntax {
    guard let seq = expr.as(SequenceExprSyntax.self),
          seq.elements.count == 3,
          seq.elements[seq.elements.index(seq.elements.startIndex, offsetBy: 1)]
              .is(UnresolvedAsExprSyntax.self)
    else { return expr }
    return stripAsCasts(ExprSyntax(seq.elements[seq.elements.startIndex]))
}
