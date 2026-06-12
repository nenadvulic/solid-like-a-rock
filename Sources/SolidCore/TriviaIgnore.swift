import Foundation
import SwiftSyntax

/// Extract the reason from a `solid:ignore <reason>` directive found in any
/// comment of the given trivia. The directive must START the comment body:
/// after stripping the comment delimiter (`//`, `///`, `/*`, `/**`) and any
/// leading whitespace, the text must begin with `solid:ignore`. Returns `nil`
/// if absent or if no (non-empty) reason follows the directive — the reason
/// is mandatory.
/// (Moved out of `ImportCollector` so security rules share the same directive.)
func solidIgnoreReason(in trivia: Trivia) -> String? {
    for piece in trivia {
        let text: String
        switch piece {
        case let .lineComment(c), let .blockComment(c),
             let .docLineComment(c), let .docBlockComment(c):
            text = c
        default:
            continue
        }
        // Strip the comment opener (longest delimiters first), then require
        // the directive to start the remaining comment body.
        var body = Substring(text)
        for delimiter in ["/**", "///", "/*", "//"] where body.hasPrefix(delimiter) {
            body = body.dropFirst(delimiter.count)
            break
        }
        body = body.drop(while: { $0 == " " || $0 == "\t" })
        guard body.hasPrefix("solid:ignore") else { continue }
        var reason = String(body.dropFirst("solid:ignore".count))
        // Trim closing comment delimiters and whitespace around the reason.
        reason = reason.trimmingCharacters(in: CharacterSet(charactersIn: " \t*/"))
        if !reason.isEmpty { return reason }
    }
    return nil
}

/// The reason given by a `// solid:ignore <reason>` directive suppressing the
/// node, or `nil` when the node is not suppressed.
///
/// Suppression granularity is the enclosing STATEMENT: the walk climbs to the
/// enclosing `CodeBlockItemSyntax` / `MemberBlockItemSyntax` (the parser
/// attaches end-of-line comments to the outermost node of the line, not to the
/// inner expression that fired), so a directive above or at the end of a
/// multi-line statement suppresses findings anywhere inside that statement.
/// The directive must start the comment body; a mid-comment mention does not
/// suppress, and the reason is mandatory.
public func solidIgnoreReason(for node: Syntax) -> String? {
    var current: Syntax? = node
    while let n = current {
        if let reason = solidIgnoreReason(in: n.leadingTrivia) { return reason }
        if let reason = solidIgnoreReason(in: n.trailingTrivia) { return reason }
        if n.is(CodeBlockItemSyntax.self) || n.is(MemberBlockItemSyntax.self) { break }
        current = n.parent
    }
    return nil
}

/// Whether a flagged node is suppressed by `// solid:ignore <reason>` on the
/// same line or the line above. Suppression granularity is the enclosing
/// STATEMENT — see `solidIgnoreReason(for:)` for the exact semantics (the
/// directive must start the comment, and the reason is mandatory).
public func hasSolidIgnore(_ node: Syntax) -> Bool {
    solidIgnoreReason(for: node) != nil
}
