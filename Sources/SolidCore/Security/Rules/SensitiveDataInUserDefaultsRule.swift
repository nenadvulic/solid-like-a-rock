import SwiftSyntax

/// PII in UserDefaults (cleartext plist on disk). Warning: unlike a
/// credential, storing e.g. a display name can be deliberate.
public struct SensitiveDataInUserDefaultsRule: SecurityRule {
    public static let id = "sensitiveDataInUserDefaults"
    /// Categories differ deliberately from the credential sibling: a stored
    /// credential is an Auth problem (tokenInUserDefaults), stored PII is a
    /// storage-choice problem ("should have been Keychain/encrypted").
    public static let category = "Keychain"
    public static let defaultSeverity = Severity.warning

    public init() {}

    public func check(_ tree: SourceFileSyntax, file: String,
                      converter: SourceLocationConverter) -> [SecurityFinding] {
        // Key-level deferral: any KEY tokenInUserDefaults matches (e.g.
        // "userToken" via "token") is entirely its finding — excluding whole
        // keys, not just shared words, guarantees one store = one finding.
        userDefaultsSetFindings(in: tree, converter: converter, words: piiNameWords,
                                excludeWords: TokenInUserDefaultsRule.words) { key in
            "PII stored in UserDefaults under '\(key)' — consider the Keychain or encrypted storage"
        }
    }
}
