import XCTest
import Yams
@testable import SolidCore

final class SecurityRulesConfigTests: XCTestCase {
    private func decode(_ yaml: String) throws -> Configuration {
        try YAMLDecoder().decode(Configuration.self, from: yaml)
    }

    func testAbsentSecuritySectionIsNil() throws {
        let config = try decode("layers:\n  - name: A\n    paths: [Sources/A/**]\n")
        XCTAssertNil(config.security)
    }

    func testMinimalSecurityOnlyConfigDecodes() throws {
        let config = try decode("security:\n  enabled: true\n")
        XCTAssertEqual(config.security?.enabled, true)
        XCTAssertTrue(config.layers.isEmpty)          // layers now optional
        XCTAssertNoThrow(try config.validate())
    }

    func testDisableAndPerRuleOverrideDecode() throws {
        let yaml = """
        security:
          enabled: true
          severity: warning
          disable: [hardcodedSecret]
          rules:
            tokenInUserDefaults:
              severity: warning
        """
        let s = try decode(yaml).security
        XCTAssertEqual(s?.severity, .warning)
        XCTAssertEqual(s?.disable, ["hardcodedSecret"])
        XCTAssertEqual(s?.rules["tokenInUserDefaults"]?.severity, .warning)
    }

    func testUnknownRuleIDInDisableThrows() throws {
        let config = try decode("security:\n  enabled: true\n  disable: [notARule]\n")
        XCTAssertThrowsError(try config.validate()) { error in
            XCTAssertEqual(error as? ConfigurationError, .unknownSecurityRule("notARule"))
        }
    }

    func testUnknownRuleIDInRulesThrows() throws {
        let yaml = "security:\n  enabled: true\n  rules:\n    notARule:\n      severity: warning\n"
        let config = try decode(yaml)
        XCTAssertThrowsError(try config.validate()) { error in
            XCTAssertEqual(error as? ConfigurationError, .unknownSecurityRule("notARule"))
        }
    }

    func testInertConfigThrowsNothingToCheck() throws {
        // No layers, no security, no visibility: nothing would ever be checked.
        let config = try decode("alwaysAllow: [Foundation]\n")
        XCTAssertThrowsError(try config.validate()) { error in
            XCTAssertEqual(error as? ConfigurationError, .nothingToCheck)
        }
    }

    func testSecurityDisabledConfigWithLayersStillValid() throws {
        let yaml = """
        layers:
          - name: A
            paths: [Sources/A/**]
        security:
          enabled: false
        """
        XCTAssertNoThrow(try decode(yaml).validate())
    }

    func testEffectiveSeverityPrecedence() throws {
        // per-rule override > global severity > built-in default
        let yaml = """
        security:
          enabled: true
          severity: warning
          rules:
            insecureHash:
              severity: error
        """
        let s = try decode(yaml).security!
        XCTAssertEqual(s.effectiveSeverity(ruleID: "insecureHash", builtInDefault: .error), .error)
        XCTAssertEqual(s.effectiveSeverity(ruleID: "hardcodedSecret", builtInDefault: .error), .warning)
        let none = try decode("security:\n  enabled: true\n").security!
        XCTAssertEqual(none.effectiveSeverity(ruleID: "httpURLLiteral", builtInDefault: .warning), .warning)
    }

    func testIsRuleEnabled() throws {
        let s = try decode("security:\n  enabled: true\n  disable: [insecureHash]\n").security!
        XCTAssertFalse(s.isEnabled(ruleID: "insecureHash"))
        XCTAssertTrue(s.isEnabled(ruleID: "hardcodedSecret"))
    }

    func testMalformedLayersThrowsAtDecode() {
        // A layer entry missing `paths` must fail loudly, not silently become [].
        let yaml = "layers:\n  - name: A\n"
        XCTAssertThrowsError(try decode(yaml))
    }

    func testMalformedSecuritySectionThrowsAtDecode() {
        // `security:` as a list is a config mistake, not "security off".
        let yaml = "layers:\n  - name: A\n    paths: [Sources/A/**]\nsecurity:\n  - enabled\n"
        XCTAssertThrowsError(try decode(yaml))
    }
}
