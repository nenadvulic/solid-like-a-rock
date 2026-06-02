import XCTest
@testable import SolidCore

/// Verifies file→layer resolution with glob-aware path matching, including the
/// backwards-compatible "bare directory fragment" behaviour and the sibling-prefix
/// bug fix (`Sources/Domain` must not capture `Sources/DomainHelpers`).
final class LayerMatchingTests: XCTestCase {
    private func linter(_ layers: [LayerRule]) -> Linter {
        Linter(config: Configuration(layers: layers))
    }

    func testBareFragmentMatchesFilesUnderDirectory() {
        let l = linter([LayerRule(name: "Domain", paths: ["Sources/Domain"])])
        XCTAssertEqual(l.layer(for: "/proj/Sources/Domain/User.swift")?.name, "Domain")
    }

    func testBareFragmentDoesNotMatchSiblingPrefix() {
        // The headline bug: a directory fragment must align on a component boundary.
        let l = linter([LayerRule(name: "Domain", paths: ["Sources/Domain"])])
        XCTAssertNil(l.layer(for: "/proj/Sources/DomainHelpers/Helper.swift"))
    }

    func testExplicitGlobMatches() {
        let l = linter([LayerRule(name: "Presentation", paths: ["SwiftUI/PresentationLayer/**"])])
        XCTAssertEqual(
            l.layer(for: "/x/SwiftUI/PresentationLayer/Booking/Sources/Booking/View.swift")?.name,
            "Presentation"
        )
    }

    func testMultipleLayersResolveByOwnPaths() {
        let l = linter([
            LayerRule(name: "Domain", paths: ["Sources/Domain", "Sources/DomainServices"]),
            LayerRule(name: "Data", paths: ["Sources/Data"]),
        ])
        XCTAssertEqual(l.layer(for: "/p/Sources/DomainServices/Svc.swift")?.name, "Domain")
        XCTAssertEqual(l.layer(for: "/p/Sources/Data/Store.swift")?.name, "Data")
    }
}
