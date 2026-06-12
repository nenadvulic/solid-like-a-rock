import XCTest
@testable import SolidCore

final class SecurityLoggingRulesTests: XCTestCase {
    // MARK: publicPIIInLog

    func testPublicEmailInterpolationIsFlagged() {
        let findings = runRule(PublicPIIInLogRule(),
            on: "logger.info(\"user: \\(email, privacy: .public)\")\n")
        XCTAssertEqual(findings.count, 1)
    }

    func testPublicTokenMemberAccessIsFlagged() {
        XCTAssertEqual(runRule(PublicPIIInLogRule(),
            on: "logger.debug(\"t=\\(session.authToken, privacy: .public)\")\n").count, 1)
    }

    func testPrivatePIIIsNotFlagged() {
        XCTAssertTrue(runRule(PublicPIIInLogRule(),
            on: "logger.info(\"user: \\(email, privacy: .private)\")\n").isEmpty)
        XCTAssertTrue(runRule(PublicPIIInLogRule(),
            on: "logger.info(\"user: \\(email)\")\n").isEmpty)   // default privacy is private
    }

    func testPublicNonPIIIsNotFlagged() {
        XCTAssertTrue(runRule(PublicPIIInLogRule(),
            on: "logger.info(\"count: \\(requestCount, privacy: .public)\")\n").isEmpty)
    }

    // MARK: printSensitiveData

    func testPrintWithPasswordIdentifierIsFlagged() {
        XCTAssertEqual(runRule(PrintSensitiveDataRule(), on: "print(password)\n").count, 1)
    }

    func testPrintWithSensitiveInterpolationIsFlagged() {
        XCTAssertEqual(runRule(PrintSensitiveDataRule(),
            on: "print(\"logging in \\(userEmail)\")\n").count, 1)
    }

    func testNSLogAndDumpAreCovered() {
        XCTAssertEqual(runRule(PrintSensitiveDataRule(), on: "NSLog(\"%@\", authToken)\n").count, 1)
        XCTAssertEqual(runRule(PrintSensitiveDataRule(), on: "dump(credentials)\n").count, 1)
    }

    func testInnocentPrintIsNotFlagged() {
        XCTAssertTrue(runRule(PrintSensitiveDataRule(), on: "print(\"app started\")\n").isEmpty)
        XCTAssertTrue(runRule(PrintSensitiveDataRule(), on: "print(itemCount)\n").isEmpty)
    }
}
