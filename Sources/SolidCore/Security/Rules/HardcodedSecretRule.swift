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
                return true
            }
        }
        let v = V(converter: converter)
        v.walk(tree)
        return v.findings
    }
}
