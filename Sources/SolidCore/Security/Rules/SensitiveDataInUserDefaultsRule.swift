import SwiftSyntax

/// PII in UserDefaults (cleartext plist on disk). Warning: unlike a
/// credential, storing e.g. a display name can be deliberate.
public struct SensitiveDataInUserDefaultsRule: SecurityRule {
    public static let id = "sensitiveDataInUserDefaults"
    public static let category = "Keychain"
    public static let defaultSeverity = Severity.warning
    /// PII words minus the secret words tokenInUserDefaults already owns (no double-flag).
    static let words = piiNameWords.filter { !TokenInUserDefaultsRule.words.contains($0) }

    public init() {}

    public func check(_ tree: SourceFileSyntax, file: String,
                      converter: SourceLocationConverter) -> [SecurityFinding] {
        userDefaultsSetFindings(in: tree, converter: converter, words: Self.words) { key in
            "PII stored in UserDefaults under '\(key)' — consider the Keychain or encrypted storage"
        }
    }
}
