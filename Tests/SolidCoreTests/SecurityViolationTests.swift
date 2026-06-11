import XCTest
@testable import SolidCore

final class SecurityViolationTests: XCTestCase {
    private let v = Violation.security(
        ruleID: "insecureHash", category: "Crypto",
        message: "Insecure.MD5 is not collision-resistant — use SHA256",
        file: "Sources/A/Hash.swift", line: 7, severity: .error)

    func testFactoryFieldMapping() {
        XCTAssertEqual(v.reason, .securityIssue)
        XCTAssertEqual(v.importedModule, "insecureHash")   // ruleID → baseline key
        XCTAssertEqual(v.layer, "Crypto")                  // category
        XCTAssertEqual(v.detail, "Insecure.MD5 is not collision-resistant — use SHA256")
    }

    func testMessageUsesDetail() {
        XCTAssertEqual(v.message, "[insecureHash] Insecure.MD5 is not collision-resistant — use SHA256")
    }

    func testDiagnosticLine() {
        XCTAssertEqual(v.diagnostic,
            "Sources/A/Hash.swift:7: error: SolidLikeARock: [insecureHash] Insecure.MD5 is not collision-resistant — use SHA256")
    }

    func testBaselineDistinguishesRulesAndIgnoresLines() throws {
        let other = Violation.security(ruleID: "hardcodedSecret", category: "Crypto",
                                       message: "x", file: "Sources/A/Hash.swift", line: 9, severity: .error)
        let baseline = Baseline(violations: [v])
        XCTAssertTrue(baseline.isKnown(Violation.security(
            ruleID: "insecureHash", category: "Crypto", message: "x",
            file: "Sources/A/Hash.swift", line: 99, severity: .error)))  // same rule, other line
        XCTAssertFalse(baseline.isKnown(other))                          // other rule
    }

    func testJSONReportRendersSecurityViolation() throws {
        let json = try renderJSON([v])
        XCTAssertTrue(json.contains("\"reason\" : \"securityIssue\""))
        XCTAssertTrue(json.contains("\"module\" : \"insecureHash\""))
        XCTAssertTrue(json.contains("\"layer\" : \"Crypto\""))
    }

    func testGitHubReporterRendersSecurityViolation() {
        XCTAssertEqual(renderGitHub([v]),
            "::error file=Sources/A/Hash.swift,line=7::SolidLikeARock: [insecureHash] Insecure.MD5 is not collision-resistant — use SHA256")
    }
}
