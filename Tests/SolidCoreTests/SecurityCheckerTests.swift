import XCTest
import SwiftSyntax
@testable import SolidCore

/// Fires once per `print` call — a trivial rule to exercise the engine.
struct StubPrintRule: SecurityRule {
    static let id = "stubPrint"
    static let category = "Logging"
    static let defaultSeverity = Severity.error
    init() {}
    func check(_ tree: SourceFileSyntax, file: String,
               converter: SourceLocationConverter) -> [SecurityFinding] {
        final class V: SyntaxVisitor {
            var found: [(Int, Syntax)] = []
            let converter: SourceLocationConverter
            init(converter: SourceLocationConverter) {
                self.converter = converter
                super.init(viewMode: .sourceAccurate)
            }
            override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
                if node.calledExpression.trimmedDescription == "print" {
                    found.append((node.startLocation(converter: converter).line, Syntax(node)))
                }
                return .visitChildren
            }
        }
        let v = V(converter: converter)
        v.walk(tree)
        return v.found.map { SecurityFinding(line: $0.0, message: "print call", node: $0.1) }
    }
}

final class SecurityCheckerTests: XCTestCase {
    private func write(_ source: String, name: String = "Test.swift") throws -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sec-checker-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent(name)
        try source.write(to: file, atomically: true, encoding: .utf8)
        return file.path
    }

    private func checker(_ config: SecurityRules) -> SecurityChecker {
        SecurityChecker(config: config, rules: [StubPrintRule()])
    }

    func testFindingBecomesViolationWithRuleMetadata() throws {
        let file = try write("print(\"hi\")\n")
        let violations = checker(SecurityRules(enabled: true)).check(swiftFiles: [file])
        XCTAssertEqual(violations.count, 1)
        XCTAssertEqual(violations[0].reason, .securityIssue)
        XCTAssertEqual(violations[0].importedModule, "stubPrint")
        XCTAssertEqual(violations[0].layer, "Logging")
        XCTAssertEqual(violations[0].severity, .error)
        XCTAssertEqual(violations[0].line, 1)
        XCTAssertEqual(violations[0].file, file)
    }

    func testDisabledRuleProducesNothing() throws {
        let file = try write("print(\"hi\")\n")
        let config = SecurityRules(enabled: true, disable: ["stubPrint"])
        XCTAssertTrue(checker(config).check(swiftFiles: [file]).isEmpty)
    }

    func testSeverityOverridesApply() throws {
        let file = try write("print(\"hi\")\n")
        let global = SecurityRules(enabled: true, severity: .warning)
        XCTAssertEqual(checker(global).check(swiftFiles: [file]).first?.severity, .warning)
        let perRule = SecurityRules(enabled: true, severity: .warning,
                                    rules: ["stubPrint": .init(severity: .error)])
        XCTAssertEqual(checker(perRule).check(swiftFiles: [file]).first?.severity, .error)
    }

    func testSolidIgnoreSuppressesFinding() throws {
        let file = try write("print(\"hi\") // solid:ignore debug build only\n")
        XCTAssertTrue(checker(SecurityRules(enabled: true)).check(swiftFiles: [file]).isEmpty)
    }

    func testUnreadableFileIsSkippedSilently() throws {
        let violations = checker(SecurityRules(enabled: true))
            .check(swiftFiles: ["/nonexistent/Nope.swift"])
        XCTAssertTrue(violations.isEmpty)
    }

    // MARK: - matchesSensitiveName

    func testSensitiveNamesMatch() {
        XCTAssertTrue(matchesSensitiveName("apiKey", words: secretNameWords))
        XCTAssertTrue(matchesSensitiveName("api_key", words: secretNameWords))
        XCTAssertTrue(matchesSensitiveName("API_KEY", words: secretNameWords))
        XCTAssertTrue(matchesSensitiveName("dbPassword", words: secretNameWords))
    }

    func testNonSensitiveNamesDoNotMatch() {
        XCTAssertFalse(matchesSensitiveName("monkey", words: secretNameWords))
        XCTAssertFalse(matchesSensitiveName("keyboardTitle", words: secretNameWords))
        XCTAssertFalse(matchesSensitiveName("launchCount", words: secretNameWords))
    }
}
