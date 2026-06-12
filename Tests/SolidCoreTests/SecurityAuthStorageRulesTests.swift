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

    func testBooleanAuthPreferencesAreNotFlagged() {
        // `auth` preference flags are not credentials; a Bool is provably not a secret.
        XCTAssertTrue(runRule(TokenInUserDefaultsRule(),
            on: "defaults.set(true, forKey: \"biometricAuthEnabled\")\n").isEmpty)
        XCTAssertTrue(runRule(TokenInUserDefaultsRule(),
            on: "UserDefaults.standard.set(false, forKey: \"requireAuthOnLaunch\")\n").isEmpty)
    }

    func testSetValueVariantIsAlsoFlagged() {
        XCTAssertEqual(runRule(TokenInUserDefaultsRule(),
            on: "UserDefaults.standard.setValue(t, forKey: \"sessionToken\")\n").count, 1)
    }

    func testCustomDefaultsWrapperIsCovered() {
        XCTAssertEqual(runRule(TokenInUserDefaultsRule(),
            on: "appDefaults.set(t, forKey: \"refreshToken\")\n").count, 1)
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
        // Rule tokenInUserDefaults (error) owns credential KEYS: any key it
        // matches is excluded here at key level, so one store = one finding.
        XCTAssertTrue(runRule(SensitiveDataInUserDefaultsRule(),
            on: "UserDefaults.standard.set(jwt, forKey: \"authToken\")\n").isEmpty)
    }

    func testUserTokenFiresOnlyTheTokenRule() {
        let src = "UserDefaults.standard.set(t, forKey: \"userToken\")\n"
        XCTAssertEqual(runRule(TokenInUserDefaultsRule(), on: src).count, 1)
        XCTAssertTrue(runRule(SensitiveDataInUserDefaultsRule(), on: src).isEmpty)
    }

    func testNonPIIPreferenceKeysAreNotFlagged() {
        for key in ["userInterfaceStyle", "hasSeenUserGuide", "displayName",
                    "deviceName", "fontName", "serverAddress"] {
            XCTAssertTrue(runRule(SensitiveDataInUserDefaultsRule(),
                on: "defaults.set(v, forKey: \"\(key)\")\n").isEmpty,
                "expected '\(key)' to be silent")
        }
    }

    func testRealPIIKeysStillFlagged() {
        for key in ["firstName", "userEmail", "phoneNumber", "homeAddress", "ssn"] {
            XCTAssertEqual(runRule(SensitiveDataInUserDefaultsRule(),
                on: "defaults.set(v, forKey: \"\(key)\")\n").count, 1,
                "expected '\(key)' to fire")
        }
    }

    // MARK: biometryNoErrorHandling

    func testCanEvaluatePolicyWithNilErrorIsFlagged() {
        let findings = runRule(BiometryNoErrorHandlingRule(),
            on: "if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) { }\n")
        XCTAssertEqual(findings.count, 1)
    }

    func testCanEvaluatePolicyResultUnusedIsNotFlagged() {
        // Regression (Signal-iOS): a bare statement call made only for its
        // documented side effect (it must precede reading biometryType) makes
        // no auth decision — there is no ignored failure path.
        XCTAssertTrue(runRule(BiometryNoErrorHandlingRule(),
            on: "context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)\n").isEmpty)
    }

    func testCanEvaluatePolicyResultBoundWithNilErrorStaysFlagged() {
        XCTAssertEqual(runRule(BiometryNoErrorHandlingRule(),
            on: "let ok = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)\n").count, 1)
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

    func testSwitchCasePatternIsNotFlagged() {
        // A `case .deviceOwnerAuthenticationWithBiometrics:` is provably HANDLING
        // a policy, not selecting one.
        let findings = runRule(BiometryNoFallbackRule(), on: """
        switch policy {
        case .deviceOwnerAuthenticationWithBiometrics: break
        default: break
        }
        """)
        XCTAssertTrue(findings.isEmpty)
    }
}
