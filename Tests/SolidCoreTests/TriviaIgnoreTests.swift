import XCTest
import SwiftParser
import SwiftSyntax
@testable import SolidCore

final class TriviaIgnoreTests: XCTestCase {
    /// Find the first function-call node of the parsed source.
    private func firstCall(in source: String) -> FunctionCallExprSyntax {
        final class Finder: SyntaxVisitor {
            var found: FunctionCallExprSyntax?
            override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
                if found == nil { found = node }
                return .skipChildren
            }
        }
        let finder = Finder(viewMode: .sourceAccurate)
        finder.walk(Parser.parse(source: source))
        return finder.found!
    }

    func testNodeWithTrailingIgnoreIsSuppressed() {
        let call = firstCall(in: "doThing() // solid:ignore legacy hashing for ETag\n")
        XCTAssertTrue(hasSolidIgnore(Syntax(call)))
    }

    func testNodeWithLeadingIgnoreIsSuppressed() {
        let call = firstCall(in: "// solid:ignore intentional\ndoThing()\n")
        XCTAssertTrue(hasSolidIgnore(Syntax(call)))
    }

    func testBareIgnoreWithoutReasonDoesNotSuppress() {
        let call = firstCall(in: "doThing() // solid:ignore\n")
        XCTAssertFalse(hasSolidIgnore(Syntax(call)))
    }

    func testPlainNodeIsNotSuppressed() {
        XCTAssertFalse(hasSolidIgnore(Syntax(firstCall(in: "doThing()\n"))))
    }

    func testIgnoreOnSameLineViaSiblingTrivia() {
        // The comment ends up in the trivia of the statement, not necessarily the
        // call node itself — the helper must look at the enclosing line statement.
        let source = "let x = make() // solid:ignore fixture\n"
        final class Finder: SyntaxVisitor {
            var found: FunctionCallExprSyntax?
            override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
                found = node; return .skipChildren
            }
        }
        let finder = Finder(viewMode: .sourceAccurate)
        finder.walk(Parser.parse(source: source))
        XCTAssertTrue(hasSolidIgnore(Syntax(finder.found!)))
    }

    func testIgnoreOnNextLineDoesNotSuppressPreviousLine() {
        let source = "doThing()\n// solid:ignore belongs to the line below\nother()\n"
        XCTAssertFalse(hasSolidIgnore(Syntax(firstCall(in: source))))
    }
}
