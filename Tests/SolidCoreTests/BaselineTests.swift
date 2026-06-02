import XCTest
@testable import SolidCore

final class BaselineTests: XCTestCase {
    private func violation(_ file: String, _ line: Int, _ module: String,
                           _ reason: Violation.Reason = .deniedImport) -> Violation {
        Violation(file: file, line: line, importedModule: module, layer: "L", reason: reason)
    }

    func testNewViolationsExcludesKnownOnes() {
        let known = violation("A.swift", 3, "UIKit")
        let fresh = violation("B.swift", 9, "Data")
        let baseline = Baseline(violations: [known])

        let result = baseline.newViolations(in: [known, fresh])
        XCTAssertEqual(result.map(\.importedModule), ["Data"])
    }

    func testBaselineIgnoresLineNumber() {
        // Same file+module+reason but a shifted line is still "known".
        let baseline = Baseline(violations: [violation("A.swift", 3, "UIKit")])
        let shifted = violation("A.swift", 42, "UIKit")
        XCTAssertTrue(baseline.newViolations(in: [shifted]).isEmpty)
    }

    func testReasonIsPartOfIdentity() {
        let baseline = Baseline(violations: [violation("A.swift", 3, "UIKit", .deniedImport)])
        let differentReason = violation("A.swift", 3, "UIKit", .outwardDependency)
        XCTAssertEqual(baseline.newViolations(in: [differentReason]).count, 1)
    }

    func testRoundTripsThroughDisk() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("solid-baseline-\(UUID().uuidString).json")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }

        let original = Baseline(violations: [violation("A.swift", 3, "UIKit"),
                                             violation("B.swift", 9, "Data")])
        try original.write(to: url.path)
        let loaded = try Baseline.load(from: url.path)

        // The previously-known violations should be filtered out by the loaded baseline.
        XCTAssertTrue(loaded.newViolations(in: [violation("A.swift", 99, "UIKit"),
                                                violation("B.swift", 1, "Data")]).isEmpty)
    }
}
