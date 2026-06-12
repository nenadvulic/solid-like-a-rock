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

    func testQualifiedCryptoKitInsecureIsFlagged() {
        XCTAssertEqual(runRule(InsecureHashRule(),
            on: "let d = CryptoKit.Insecure.MD5.hash(data: data)\n").count, 1)
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

    func testCommonIOSStringIdiomsAreNotFlagged() {
        // Header name — a label, not a secret.
        XCTAssertTrue(runRule(HardcodedSecretRule(), on: "let apiKeyHeader = \"X-Api-Key\"\n").isEmpty)
        // URL — endpoints are not secrets.
        XCTAssertTrue(runRule(HardcodedSecretRule(),
            on: "static let tokenEndpoint = \"https://auth.example.com/token\"\n").isEmpty)
        // Keypath / reverse-DNS UserDefaults keys — the most common iOS string idiom.
        XCTAssertTrue(runRule(HardcodedSecretRule(), on: "let keyPath = \"user.profile.image\"\n").isEmpty)
        XCTAssertTrue(runRule(HardcodedSecretRule(), on: "let lastSyncKey = \"com.app.lastSyncDate\"\n").isEmpty)
        // Notification.Name-style values.
        XCTAssertTrue(runRule(HardcodedSecretRule(),
            on: "static let tokenRefreshed = \"tokenRefreshedNotification\"\n").isEmpty)
    }

    func testStorageKeyNameValuesAreNotFlagged() {
        // Regression (Signal-iOS): key-named constants whose VALUE is itself an
        // identifier-shaped key NAME (storage/notification/header keys), not a secret.
        XCTAssertTrue(runRule(HardcodedSecretRule(),
            on: "static let keyValueStoreCollectionName = \"kTSStorageManager_OWSDeviceCollection\"\n").isEmpty)
        XCTAssertTrue(runRule(HardcodedSecretRule(),
            on: "private let firstVersionKey = \"kNSUserDefaults_FirstAppVersion\"\n").isEmpty)
        // Header name with an algorithm suffix — short trailing digit runs are word-like.
        XCTAssertTrue(runRule(HardcodedSecretRule(),
            on: "static let checksumHeaderKey = \"x-signal-checksum-sha256\"\n").isEmpty)
        // REST path.
        XCTAssertTrue(runRule(HardcodedSecretRule(),
            on: "static let textSecureSignedKeysAPI = \"v2/keys/signed\"\n").isEmpty)
        // Human-readable phrase.
        XCTAssertTrue(runRule(HardcodedSecretRule(),
            on: "let screenSecurityKey = \"Screen Security Key\"\n").isEmpty)
        // Mixed _ and - separators.
        XCTAssertTrue(runRule(HardcodedSecretRule(),
            on: "private let kUDCurrentSenderCertificateKey = \"kUDCurrentSenderCertificateKey_Production-uuid\"\n").isEmpty)
    }

    func testValueEchoingItsOwnIdentifierIsNotFlagged() {
        // Regression (Signal-iOS): a literal equal to its own variable name is a
        // key NAME by construction. The interior digit in "2FA" defeats the
        // word-shape gate, so the name-echo gate must catch it.
        XCTAssertTrue(runRule(HardcodedSecretRule(),
            on: "private let kOWS2FAManager_LastSuccessfulReminderDateKey = \"kOWS2FAManager_LastSuccessfulReminderDateKey\"\n").isEmpty)
    }

    func testRandomLookingSecretsStayFlaggedDespiteSeparators() {
        // Long trailing digit run is not word-shaped.
        XCTAssertEqual(runRule(HardcodedSecretRule(),
            on: "let apiKey = \"sk-live-abcdef123456\"\n").count, 1)
        // Interior digits (AWS-style segments) are not word-shaped.
        XCTAssertEqual(runRule(HardcodedSecretRule(),
            on: "let awsSecretKey = \"wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY\"\n").count, 1)
    }

    func testJWTStaysFlaggedDespiteDots() {
        // Dotted-identifier filter must NOT swallow JWTs: base64url segments are long.
        let jwt = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dBjftJeZ4CVPmB92K27uhbUJU1p1r_wW1gFWFOEjXk" // solid:ignore test fixture, deliberately secret-shaped for the rule under test
        XCTAssertEqual(runRule(HardcodedSecretRule(), on: "let authToken = \"\(jwt)\"\n").count, 1)
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

    func testHexEncodedKeyIsFlagged() {
        // 64-char hex (a SHA-256-sized key). Pure hex caps at 4.0 bits/char,
        // so it needs its own gate — the base64 threshold can't reach it.
        let hex = "3f786850e387550fdab836ed7e6dc881de23001b1a9a3f4d9aab2c2f8b7e2d4a" // solid:ignore test fixture, deliberately key-shaped for the rule under test
        XCTAssertEqual(runRule(HighEntropySecretRule(), on: "let k = \"\(hex)\"\n").count, 1)
    }

    func testAlphabetConstantsAreNotFlagged() {
        // Regression: self-lint flagged the base64 alphabet inside this very rule.
        // Alphabet/charset tables are high-entropy by construction but every
        // character is distinct — real secrets repeat characters at this length.
        XCTAssertTrue(runRule(HighEntropySecretRule(),
            on: "let base64 = \"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=\"\n").isEmpty)
        // base64url variant.
        XCTAssertTrue(runRule(HighEntropySecretRule(),
            on: "let b64url = \"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789\"\n").isEmpty)
    }

    func testEnglishHexLikeWordsAreNotFlagged() {
        // Short or low-entropy hex-charset strings stay silent.
        XCTAssertTrue(runRule(HighEntropySecretRule(), on: "let s = \"deadbeefdeadbeefdeadbeef\"\n").isEmpty)
        XCTAssertTrue(runRule(HighEntropySecretRule(), on: "let s = \"cafebabe\"\n").isEmpty)
    }
}
