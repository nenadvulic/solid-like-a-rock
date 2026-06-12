import XCTest
import SwiftParser
import SwiftSyntax
@testable import SolidCore

/// Shared harness: run one rule over an inline source string.
func runRule(_ rule: any SecurityRule, on source: String,
             file: String = "Test.swift") -> [SecurityFinding] {
    let tree = Parser.parse(source: source)
    let converter = SourceLocationConverter(fileName: file, tree: tree)
    return rule.check(tree, file: file, converter: converter)
}

final class SecurityKeychainRulesTests: XCTestCase {
    // MARK: keychainAccessibleAlways

    func testAccessibleAlwaysIsFlagged() {
        let findings = runRule(KeychainAccessibleAlwaysRule(), on: """
        let query: [String: Any] = [
            kSecAttrAccessible as String: kSecAttrAccessibleAlways,
        ]
        """)
        XCTAssertEqual(findings.count, 1)
        XCTAssertEqual(findings[0].line, 2)
        XCTAssertTrue(findings[0].message.contains("kSecAttrAccessibleAlways"))
    }

    func testAccessibleAlwaysThisDeviceOnlyIsFlagged() {
        let findings = runRule(KeychainAccessibleAlwaysRule(),
                               on: "let a = kSecAttrAccessibleAlwaysThisDeviceOnly\n")
        XCTAssertEqual(findings.count, 1)
        // The longer identifier must be reported, not its prefix.
        XCTAssertTrue(findings[0].message.contains("kSecAttrAccessibleAlwaysThisDeviceOnly"))
    }

    func testWhenUnlockedIsNotFlagged() {
        XCTAssertTrue(runRule(KeychainAccessibleAlwaysRule(),
                              on: "let a = kSecAttrAccessibleWhenUnlockedThisDeviceOnly\n").isEmpty)
    }

    // MARK: keychainMissingAccessibility

    func testSecItemAddWithInlineDictMissingAccessibilityIsFlagged() {
        let findings = runRule(KeychainMissingAccessibilityRule(), on: """
        let status = SecItemAdd([
            kSecClass as String: kSecClassGenericPassword,
            kSecValueData as String: data,
        ] as CFDictionary, nil)
        """)
        XCTAssertEqual(findings.count, 1)
        XCTAssertEqual(findings[0].line, 1)
    }

    func testSecItemAddViaLocalVariableMissingAccessibilityIsFlagged() {
        let findings = runRule(KeychainMissingAccessibilityRule(), on: """
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        """)
        XCTAssertEqual(findings.count, 1)
        XCTAssertEqual(findings[0].line, 4)
    }

    func testSecItemAddWithAccessibilityIsNotFlagged() {
        let findings = runRule(KeychainMissingAccessibilityRule(), on: """
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        """)
        XCTAssertTrue(findings.isEmpty)
    }

    func testSecItemAddWithDynamicDictIsNotFlagged() {
        // Built elsewhere / mutated — no literal proof, stay silent.
        let findings = runRule(KeychainMissingAccessibilityRule(), on: """
        let status = SecItemAdd(makeQuery() as CFDictionary, nil)
        """)
        XCTAssertTrue(findings.isEmpty)
    }
}
