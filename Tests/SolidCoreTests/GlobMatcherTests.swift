import XCTest
@testable import SolidCore

/// Tests for the dependency-light path glob matcher.
///
/// Semantics (gitignore-style):
/// - `*`  matches within a single path segment (never crosses `/`)
/// - `**` matches across segments (any number, including zero)
/// - `?`  matches exactly one non-`/` character
/// - a pattern matches if it lines up on COMPONENT boundaries anywhere in the
///   path, so `Sources/Domain/**` also matches an absolute `/a/b/Sources/Domain/x.swift`
final class GlobMatcherTests: XCTestCase {
    func testStarStaysWithinOneSegment() {
        XCTAssertTrue(globMatch("Sources/Domain/User.swift", pattern: "Sources/Domain/*.swift"))
        // `*` must NOT cross a separator
        XCTAssertFalse(globMatch("Sources/Domain/Sub/User.swift", pattern: "Sources/Domain/*.swift"))
    }

    func testDoubleStarCrossesSegments() {
        XCTAssertTrue(globMatch("Sources/Domain/User.swift", pattern: "Sources/Domain/**"))
        XCTAssertTrue(globMatch("Sources/Domain/Sub/Deep/User.swift", pattern: "Sources/Domain/**"))
    }

    func testComponentBoundaryRulesOutSiblingPrefix() {
        // The whole point: Sources/Domain must NOT match Sources/DomainHelpers.
        XCTAssertTrue(globMatch("proj/Sources/Domain/User.swift", pattern: "Sources/Domain/**"))
        XCTAssertFalse(globMatch("proj/Sources/DomainHelpers/User.swift", pattern: "Sources/Domain/**"))
    }

    func testMatchesInsideAbsolutePath() {
        let abs = "/Users/x/proj/Sources/Domain/Entity.swift"
        XCTAssertTrue(globMatch(abs, pattern: "Sources/Domain/**"))
    }

    func testQuestionMarkMatchesSingleChar() {
        XCTAssertTrue(globMatch("a/File1.swift", pattern: "a/File?.swift"))
        XCTAssertFalse(globMatch("a/File12.swift", pattern: "a/File?.swift"))
    }
}
