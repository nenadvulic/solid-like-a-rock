import XCTest
@testable import SolidCore

/// The GitHub reporter emits workflow commands so violations surface as inline
/// annotations on a pull request.
final class GitHubReporterTests: XCTestCase {
    func testErrorEmitsErrorAnnotation() {
        let v = Violation(file: "Sources/Domain/X.swift", line: 5, importedModule: "UIKit",
                          layer: "Domain", reason: .deniedImport, severity: .error)
        let line = renderGitHub([v])
        XCTAssertEqual(
            line,
            "::error file=Sources/Domain/X.swift,line=5::SolidLikeARock: layer 'Domain' must not import 'UIKit'"
        )
    }

    func testWarningEmitsWarningAnnotation() {
        let v = Violation(file: "A.swift", line: 2, importedModule: "Data",
                          layer: "Presentation", reason: .deniedImport, severity: .warning)
        XCTAssertTrue(renderGitHub([v]).hasPrefix("::warning file=A.swift,line=2::"), renderGitHub([v]))
    }

    func testOneLinePerViolation() {
        let vs = [
            Violation(file: "A.swift", line: 1, importedModule: "X", layer: "L", reason: .deniedImport),
            Violation(file: "B.swift", line: 2, importedModule: "Y", layer: "L", reason: .deniedImport),
        ]
        XCTAssertEqual(renderGitHub(vs).split(separator: "\n").count, 2)
    }
}
