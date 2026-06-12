import Foundation
import SwiftSyntax

/// Extract the reason from a `solid:ignore <reason>` directive found in any
/// comment of the given trivia. Returns `nil` if absent or if no (non-empty)
/// reason follows the directive — the reason is mandatory.
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
        guard let range = text.range(of: "solid:ignore") else { continue }
        var reason = String(text[range.upperBound...])
        // Trim comment delimiters and whitespace around the reason.
        reason = reason.trimmingCharacters(in: CharacterSet(charactersIn: " \t*/"))
        if !reason.isEmpty { return reason }
    }
    return nil
}

/// Whether a flagged node is suppressed by `// solid:ignore <reason>` on the
/// same line (trailing trivia of the enclosing statement) or the line above
/// (leading trivia). Walks up to the enclosing `CodeBlockItemSyntax` /
/// `MemberBlockItemSyntax` because the parser attaches end-of-line comments to
/// the outermost node of the line, not to the inner expression that fired.
public func hasSolidIgnore(_ node: Syntax) -> Bool {
    var current: Syntax? = node
    while let n = current {
        if solidIgnoreReason(in: n.leadingTrivia) != nil { return true }
        if solidIgnoreReason(in: n.trailingTrivia) != nil { return true }
        if n.is(CodeBlockItemSyntax.self) || n.is(MemberBlockItemSyntax.self) { break }
        current = n.parent
    }
    // The trailing comment of the LAST statement on a line can also be attached
    // as the leading trivia of the NEXT token — check the next token too, but
    // only when no newline precedes the comment (a comment on a LATER line
    // belongs to the next statement, not to this one).
    if let item = node.enclosingLineItem(),
       let next = item.lastToken(viewMode: .sourceAccurate)?
           .nextToken(viewMode: .sourceAccurate),
       solidIgnoreReason(in: next.leadingTrivia) != nil,
       !next.leadingTrivia.containsNewlineBeforeComment {
        return true
    }
    return false
}

extension Syntax {
    /// The statement-level ancestor that owns this node's source line.
    func enclosingLineItem() -> Syntax? {
        var current: Syntax? = self
        while let n = current {
            if n.is(CodeBlockItemSyntax.self) || n.is(MemberBlockItemSyntax.self) { return n }
            current = n.parent
        }
        return nil
    }
}

extension Trivia {
    /// True when a newline appears before the first comment piece — i.e. the
    /// comment is on a LATER line, so it must not suppress the previous line.
    var containsNewlineBeforeComment: Bool {
        for piece in self {
            switch piece {
            case .newlines, .carriageReturns, .carriageReturnLineFeeds:
                return true
            case .lineComment, .blockComment, .docLineComment, .docBlockComment:
                return false
            default:
                continue
            }
        }
        return false
    }
}
