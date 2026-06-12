import SwiftSyntax

/// Find `….set(_, forKey: "literal")` calls on a UserDefaults-looking base
/// (`UserDefaults.standard`, `defaults`, …) whose key matches `words`.
/// Conservative: non-literal keys never match.
func userDefaultsSetFindings(in tree: SourceFileSyntax,
                             converter: SourceLocationConverter,
                             words: [String],
                             message: @escaping (String) -> String) -> [SecurityFinding] {
    final class V: SyntaxVisitor {
        var findings: [SecurityFinding] = []
        let converter: SourceLocationConverter
        let words: [String]
        let message: (String) -> String
        init(converter: SourceLocationConverter, words: [String], message: @escaping (String) -> String) {
            self.converter = converter
            self.words = words
            self.message = message
            super.init(viewMode: .sourceAccurate)
        }
        override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
            guard let member = node.calledExpression.as(MemberAccessExprSyntax.self),
                  member.declName.baseName.text == "set",
                  Self.baseLooksLikeUserDefaults(member.base),
                  let keyArg = node.arguments.first(where: { $0.label?.text == "forKey" }),
                  let literal = keyArg.expression.as(StringLiteralExprSyntax.self),
                  let key = plainTextValue(of: literal),
                  matchesSensitiveName(key, words: words)
            else { return .visitChildren }
            findings.append(SecurityFinding(
                line: node.startLocation(converter: converter).line,
                message: message(key), node: Syntax(node)))
            return .visitChildren
        }
        static func baseLooksLikeUserDefaults(_ base: ExprSyntax?) -> Bool {
            guard let text = base?.trimmedDescription.lowercased() else { return false }
            return text.contains("userdefaults") || text.contains("defaults")
        }
    }
    let v = V(converter: converter, words: words, message: message)
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
