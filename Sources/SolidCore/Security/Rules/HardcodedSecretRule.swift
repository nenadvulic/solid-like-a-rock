import SwiftSyntax

/// A non-placeholder string literal assigned to a secret-named identifier
/// (apiKey, password, token, …). Name heuristic only; entropy lives in
/// `highEntropySecret`.
public struct HardcodedSecretRule: SecurityRule {
    public static let id = "hardcodedSecret"
    public static let category = "Crypto"
    public static let defaultSeverity = Severity.error

    static let placeholders: Set<String> = ["changeme", "your_api_key", "placeholder", "xxx", "todo", "secret", "password"]

    public init() {}

    public func check(_ tree: SourceFileSyntax, file: String,
                      converter: SourceLocationConverter) -> [SecurityFinding] {
        final class V: SyntaxVisitor {
            var findings: [SecurityFinding] = []
            let converter: SourceLocationConverter
            init(converter: SourceLocationConverter) {
                self.converter = converter
                super.init(viewMode: .sourceAccurate)
            }
            override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
                for binding in node.bindings {
                    guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
                          matchesSensitiveName(name, words: secretNameWords),
                          let literal = binding.initializer?.value.as(StringLiteralExprSyntax.self),
                          let value = plainTextValue(of: literal),
                          // A literal that echoes its own identifier is a key
                          // NAME by construction, never a secret value.
                          value != name,
                          Self.looksLikeRealSecret(value) else { continue }
                    findings.append(SecurityFinding(
                        line: binding.startLocation(converter: converter).line,
                        message: "'\(name)' is assigned a hardcoded value — load secrets from the environment, a config file outside VCS, or the Keychain",
                        node: Syntax(binding)))
                }
                return .visitChildren
            }
            static func looksLikeRealSecret(_ value: String) -> Bool {
                guard value.count >= 8 else { return false }
                if value.hasPrefix("${") || value.hasPrefix("<") { return false }
                let lowered = value.lowercased()
                if HardcodedSecretRule.placeholders.contains(lowered) { return false }
                if lowered.contains("your_") || lowered.contains("your-") { return false }
                // URLs are endpoints, not secrets.
                if value.contains("://") { return false }
                // Keypath / reverse-DNS shapes (UserDefaults keys, bundle ids); JWT
                // base64url segments exceed the per-segment cap, so JWTs still fire.
                if isDottedIdentifier(value) { return false }
                // Header-name shapes like "X-Api-Key" are labels, not secrets.
                if isHeaderName(value) { return false }
                // Single pure-alpha words ("tokenRefreshedNotification") are overwhelmingly
                // identifiers/names. Trade-off: an alpha-only password with no digits or
                // separators is exempted too — accepted; real secrets carry digit/symbol entropy.
                if !value.isEmpty && value.allSatisfy(isASCIILetter) { return false }
                // Identifier-shaped phrases are key NAMES, not secrets:
                // "kNSUserDefaults_FirstAppVersion", "x-signal-checksum-sha256",
                // "v2/keys/signed", "Screen Security Key". Random keys fail the
                // word shape via interior digits ("K7MDENG") or long digit runs
                // ("abcdef123456").
                if isIdentifierPhrase(value) { return false }
                return true
            }
            /// `word(sep word)+` with sep in `_ - / space` and every word
            /// shaped `[A-Za-z]+[0-9]{0,3}` — letters with at most a short
            /// trailing digit run ("sha256", "v2", "Production").
            static func isIdentifierPhrase(_ value: String) -> Bool {
                let words = value.split(omittingEmptySubsequences: false,
                                        whereSeparator: { "_-/ ".contains($0) })
                guard words.count >= 2 else { return false }
                return words.allSatisfy(isWordShaped)
            }
            static func isWordShaped(_ word: Substring) -> Bool {
                guard !word.isEmpty else { return false }
                guard let firstNonLetter = word.firstIndex(where: { !isASCIILetter($0) }) else {
                    return true // pure-alpha word
                }
                guard firstNonLetter != word.startIndex else { return false }
                let digits = word[firstNonLetter...]
                return digits.count <= 3 && digits.allSatisfy { ("0"..."9").contains($0) }
            }
            /// `seg(.seg)+` where every segment is an identifier (`[A-Za-z_][A-Za-z0-9_-]*`)
            /// of at most 20 characters.
            static func isDottedIdentifier(_ value: String) -> Bool {
                let segments = value.split(separator: ".", omittingEmptySubsequences: false)
                guard segments.count >= 2 else { return false }
                return segments.allSatisfy { seg in
                    guard seg.count <= 20, let first = seg.first,
                          isASCIILetter(first) || first == "_" else { return false }
                    return seg.dropFirst().allSatisfy { isASCIILetter($0) || $0.isNumber || $0 == "_" || $0 == "-" }
                }
            }
            /// `Word(-Word)+` with alpha-only words, e.g. "X-Api-Key".
            static func isHeaderName(_ value: String) -> Bool {
                let words = value.split(separator: "-", omittingEmptySubsequences: false)
                guard words.count >= 2 else { return false }
                return words.allSatisfy { !$0.isEmpty && $0.allSatisfy(isASCIILetter) }
            }
            static func isASCIILetter(_ c: Character) -> Bool {
                ("a"..."z").contains(c) || ("A"..."Z").contains(c)
            }
        }
        let v = V(converter: converter)
        v.walk(tree)
        return v.findings
    }
}
