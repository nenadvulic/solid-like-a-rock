import XCTest
@testable import SolidCore

final class SecurityAuthStorageRulesTests: XCTestCase {
    // MARK: tokenInUserDefaults

    func testTokenKeyIsFlagged() {
        let findings = runRule(TokenInUserDefaultsRule(),
                               on: "UserDefaults.standard.set(jwt, forKey: \"authToken\")\n")
        XCTAssertEqual(findings.count, 1)
    }

    func testPasswordAndJWTKeysAreFlagged() {
        XCTAssertEqual(runRule(TokenInUserDefaultsRule(),
            on: "defaults.set(p, forKey: \"user_password\")\n").count, 1)
        XCTAssertEqual(runRule(TokenInUserDefaultsRule(),
            on: "UserDefaults.standard.set(t, forKey: \"JWT\")\n").count, 1)
    }

    func testInnocentKeyAndNonLiteralKeyAreNotFlagged() {
        XCTAssertTrue(runRule(TokenInUserDefaultsRule(),
            on: "UserDefaults.standard.set(v, forKey: \"launchCount\")\n").isEmpty)
        XCTAssertTrue(runRule(TokenInUserDefaultsRule(),
            on: "UserDefaults.standard.set(v, forKey: dynamicKey)\n").isEmpty)
    }

    // MARK: sensitiveDataInUserDefaults

    func testEmailKeyIsFlaggedByPIIRule() {
        XCTAssertEqual(runRule(SensitiveDataInUserDefaultsRule(),
            on: "UserDefaults.standard.set(v, forKey: \"userEmail\")\n").count, 1)
    }

    func testSSNKeyIsFlagged() {
        XCTAssertEqual(runRule(SensitiveDataInUserDefaultsRule(),
            on: "defaults.set(v, forKey: \"ssn\")\n").count, 1)
    }

    func testTokenKeyIsNotDoubleFlaggedByPIIRule() {
        // Rule tokenInUserDefaults (error) owns secret-words; this rule only fires
        // on PII words NOT covered by it, so one store = one finding.
        XCTAssertTrue(runRule(SensitiveDataInUserDefaultsRule(),
            on: "UserDefaults.standard.set(jwt, forKey: \"authToken\")\n").isEmpty)
    }

    // MARK: biometryNoErrorHandling

    func testCanEvaluatePolicyWithNilErrorIsFlagged() {
        let findings = runRule(BiometryNoErrorHandlingRule(),
            on: "if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) { }\n")
        XCTAssertEqual(findings.count, 1)
    }

    func testCanEvaluatePolicyWithErrorPointerIsNotFlagged() {
        XCTAssertTrue(runRule(BiometryNoErrorHandlingRule(),
            on: "if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) { }\n").isEmpty)
    }

    // MARK: biometryNoFallback

    func testBiometricsOnlyPolicyIsFlagged() {
        let findings = runRule(BiometryNoFallbackRule(),
            on: "context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: r) { ok, err in }\n")
        XCTAssertEqual(findings.count, 1)
        XCTAssertTrue(findings[0].message.contains("deviceOwnerAuthentication"))
    }

    func testPolicyWithPasscodeFallbackIsNotFlagged() {
        XCTAssertTrue(runRule(BiometryNoFallbackRule(),
            on: "context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: r) { ok, err in }\n").isEmpty)
    }
}
