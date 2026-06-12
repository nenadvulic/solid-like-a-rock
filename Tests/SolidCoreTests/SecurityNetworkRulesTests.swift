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
}
