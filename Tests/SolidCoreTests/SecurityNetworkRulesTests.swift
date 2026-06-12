import XCTest
@testable import SolidCore

final class SecurityNetworkRulesTests: XCTestCase {
    // MARK: disabledTLSValidation

    func testTrustAllDelegateIsFlagged() {
        let findings = runRule(DisabledTLSValidationRule(), on: """
        class Insecure: NSObject, URLSessionDelegate {
            func urlSession(_ session: URLSession,
                            didReceive challenge: URLAuthenticationChallenge,
                            completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
                completionHandler(.useCredential, URLCredential(trust: challenge.protectionSpace.serverTrust!))
            }
        }
        """)
        XCTAssertEqual(findings.count, 1)
        XCTAssertEqual(findings[0].line, 5)
    }

    func testDelegateThatEvaluatesTrustIsNotFlagged() {
        let findings = runRule(DisabledTLSValidationRule(), on: """
        class Pinned: NSObject, URLSessionDelegate {
            func urlSession(_ session: URLSession,
                            didReceive challenge: URLAuthenticationChallenge,
                            completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
                let trust = challenge.protectionSpace.serverTrust!
                guard SecTrustEvaluateWithError(trust, nil) else {
                    return completionHandler(.cancelAuthenticationChallenge, nil)
                }
                completionHandler(.useCredential, URLCredential(trust: trust))
            }
        }
        """)
        XCTAssertTrue(findings.isEmpty)
    }

    func testUnrelatedFunctionIsNotFlagged() {
        XCTAssertTrue(runRule(DisabledTLSValidationRule(),
            on: "func ok() { completionHandler(.useCredential, cred) }\n").isEmpty)
    }

    // MARK: httpURLLiteral

    func testHttpLiteralIsFlagged() {
        XCTAssertEqual(runRule(HttpURLLiteralRule(),
            on: "let url = URL(string: \"http://api.example.com/v1\")\n").count, 1)
    }

    func testHttpsAndLocalhostAreNotFlagged() {
        XCTAssertTrue(runRule(HttpURLLiteralRule(),
            on: "let url = URL(string: \"https://api.example.com\")\n").isEmpty)
        XCTAssertTrue(runRule(HttpURLLiteralRule(),
            on: "let url = URL(string: \"http://localhost:8080\")\n").isEmpty)
        XCTAssertTrue(runRule(HttpURLLiteralRule(),
            on: "let url = URL(string: \"http://127.0.0.1:8080\")\n").isEmpty)
        XCTAssertTrue(runRule(HttpURLLiteralRule(),
            on: "let url = URL(string: \"http://dev.local/api\")\n").isEmpty)
    }

    func testWrapperPinningIsNotFlagged() {
        // TrustKit-style: validation lives in a helper; a cancel branch proves
        // validation logic exists — never flag code that can reject the challenge.
        let findings = runRule(DisabledTLSValidationRule(), on: """
        class Pinner: NSObject, URLSessionDelegate {
            func urlSession(_ session: URLSession,
                            didReceive challenge: URLAuthenticationChallenge,
                            completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
                let trust = challenge.protectionSpace.serverTrust!
                guard CertificatePinner.shared.validate(trust) else {
                    return completionHandler(.cancelAuthenticationChallenge, nil)
                }
                completionHandler(.useCredential, URLCredential(trust: trust))
            }
        }
        """)
        XCTAssertTrue(findings.isEmpty)
    }

    func testCommentedSecTrustEvaluateDoesNotSuppress() {
        // A TODO comment must not silence a genuine trust-all.
        let findings = runRule(DisabledTLSValidationRule(), on: """
        class Insecure: NSObject, URLSessionDelegate {
            func urlSession(_ session: URLSession,
                            didReceive challenge: URLAuthenticationChallenge,
                            completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
                // TODO: call SecTrustEvaluate before trusting
                completionHandler(.useCredential, URLCredential(trust: challenge.protectionSpace.serverTrust!))
            }
        }
        """)
        XCTAssertEqual(findings.count, 1)
    }

    func testIPv6LoopbackIsNotFlagged() {
        XCTAssertTrue(runRule(HttpURLLiteralRule(),
            on: "let url = URL(string: \"http://::1/health\")\n").isEmpty)
        XCTAssertTrue(runRule(HttpURLLiteralRule(),
            on: "let url = URL(string: \"http://[::1]:8080/x\")\n").isEmpty)
    }

    func testXMLNamespaceAndPrefixStringsAreNotFlagged() {
        // Opaque identifiers, never fetched — the classic FP for this rule class.
        XCTAssertTrue(runRule(HttpURLLiteralRule(),
            on: "let ns = \"http://www.w3.org/2000/svg\"\n").isEmpty)
        XCTAssertTrue(runRule(HttpURLLiteralRule(),
            on: "let s = \"http://schemas.android.com/apk/res\"\n").isEmpty)
        XCTAssertTrue(runRule(HttpURLLiteralRule(),
            on: "let dtd = \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\"\n").isEmpty)
        // Bare prefix used for checks like url.hasPrefix("http://").
        XCTAssertTrue(runRule(HttpURLLiteralRule(),
            on: "if url.hasPrefix(\"http://\") { }\n").isEmpty)
    }
}
