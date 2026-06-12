import SwiftSyntax

/// A credential in UserDefaults is stored in cleartext on disk; there is no
/// legitimate variant of this — use the Keychain. Error by default.
public struct TokenInUserDefaultsRule: SecurityRule {
    public static let id = "tokenInUserDefaults"
    public static let category = "Auth"
    public static let defaultSeverity = Severity.error
    /// Secret words owned by THIS rule; the PII sibling excludes keys matching them.
    /// No bare "auth": it overwhelmingly names preference flags
    /// (`biometricAuthEnabled`, `requireAuthOnLaunch`), not credentials. Real
    /// credentials are still caught via token/secret/password/jwt/credential
    /// (e.g. `authToken` matches "token").
    static let words = ["token", "jwt", "password", "secret", "credential"]

    public init() {}

    public func check(_ tree: SourceFileSyntax, file: String,
                      converter: SourceLocationConverter) -> [SecurityFinding] {
        userDefaultsSetFindings(in: tree, converter: converter, words: Self.words) { key in
            "credential stored in UserDefaults under '\(key)' — UserDefaults is cleartext on disk; use the Keychain"
        }
    }
}
