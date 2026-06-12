import XCTest
@testable import SolidCore

final class SecurityCryptoRulesTests: XCTestCase {
    // MARK: insecureHash

    func testInsecureMD5IsFlagged() {
        let findings = runRule(InsecureHashRule(), on: "let d = Insecure.MD5.hash(data: data)\n")
        XCTAssertEqual(findings.count, 1)
        XCTAssertTrue(findings[0].message.contains("MD5"))
    }

    func testInsecureSHA1AndCommonCryptoAreFlagged() {
        XCTAssertEqual(runRule(InsecureHashRule(), on: "let d = Insecure.SHA1.hash(data: data)\n").count, 1)
        XCTAssertEqual(runRule(InsecureHashRule(), on: "CC_MD5(bytes, len, &digest)\n").count, 1)
        XCTAssertEqual(runRule(InsecureHashRule(), on: "CC_SHA1(bytes, len, &digest)\n").count, 1)
    }

    func testSHA256IsNotFlagged() {
        XCTAssertTrue(runRule(InsecureHashRule(), on: "let d = SHA256.hash(data: data)\n").isEmpty)
    }

    // MARK: hardcodedSecret

    func testSecretNamedLiteralIsFlagged() {
        let findings = runRule(HardcodedSecretRule(), on: "let apiKey = \"sk-live-abcdef123456\"\n")
        XCTAssertEqual(findings.count, 1)
        XCTAssertEqual(findings[0].line, 1)
    }

    func testPasswordPropertyIsFlagged() {
        XCTAssertEqual(runRule(HardcodedSecretRule(),
                               on: "struct C { static let dbPassword = \"hunter2hunter2\" }\n").count, 1)
    }

    func testPlaceholderAndShortValuesAreNotFlagged() {
        XCTAssertTrue(runRule(HardcodedSecretRule(), on: "let apiKey = \"\"\n").isEmpty)
        XCTAssertTrue(runRule(HardcodedSecretRule(), on: "let apiKey = \"changeme\"\n").isEmpty)
        XCTAssertTrue(runRule(HardcodedSecretRule(), on: "let apiKey = \"YOUR_API_KEY\"\n").isEmpty)
        XCTAssertTrue(runRule(HardcodedSecretRule(), on: "let apiKey = \"${API_KEY}\"\n").isEmpty)
        XCTAssertTrue(runRule(HardcodedSecretRule(), on: "let apiKey = \"<insert>\"\n").isEmpty)
        XCTAssertTrue(runRule(HardcodedSecretRule(), on: "let apiKey = \"short\"\n").isEmpty)
    }

    func testNonSecretNameIsNotFlagged() {
        XCTAssertTrue(runRule(HardcodedSecretRule(), on: "let monkey = \"longvaluehere123\"\n").isEmpty)
        XCTAssertTrue(runRule(HardcodedSecretRule(), on: "let keyboardTitle = \"Press any key here\"\n").isEmpty)
    }

    func testInterpolatedValueIsNotFlagged() {
        // Interpolation = not a hardcoded constant.
        XCTAssertTrue(runRule(HardcodedSecretRule(), on: "let token = \"prefix-\\(dynamic)\"\n").isEmpty)
    }

    // MARK: highEntropySecret

    func testHighEntropyBase64LiteralIsFlagged() {
        let findings = runRule(HighEntropySecretRule(),
                               on: "let blob = \"dGhpc2lzYXZlcnlsb25nc2VjcmV0a2V5MTIzNDU2Nzg5MA==\"\n")
        XCTAssertEqual(findings.count, 1)
    }

    func testLowEntropyAndNonCharsetLiteralsAreNotFlagged() {
        XCTAssertTrue(runRule(HighEntropySecretRule(),
                              on: "let s = \"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"\n").isEmpty)   // low entropy
        XCTAssertTrue(runRule(HighEntropySecretRule(),
                              on: "let s = \"This is a normal English sentence here.\"\n").isEmpty) // spaces → not base64/hex charset
        XCTAssertTrue(runRule(HighEntropySecretRule(), on: "let s = \"short\"\n").isEmpty)     // < 20 chars
    }
}
