import SwiftSyntax

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
