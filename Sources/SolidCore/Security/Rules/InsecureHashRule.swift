import SwiftSyntax

/// MD5 and SHA-1 are broken for security purposes. Flags CryptoKit's
/// `Insecure.MD5`/`Insecure.SHA1` and CommonCrypto's `CC_MD5`/`CC_SHA1`.
/// Non-security uses (ETag, dedup) should carry `// solid:ignore <reason>`.
public struct InsecureHashRule: SecurityRule {
    public static let id = "insecureHash"
    public static let category = "Crypto"
    public static let defaultSeverity = Severity.error

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
            override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
                // Insecure.MD5 / Insecure.SHA1 (any deeper member access included).
                if let base = node.base?.as(DeclReferenceExprSyntax.self),
                   base.baseName.text == "Insecure",
                   ["MD5", "SHA1"].contains(node.declName.baseName.text) {
                    add(node.declName.baseName.text, Syntax(node))
                    return .skipChildren
                }
                return .visitChildren
            }
            override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
                if ["CC_MD5", "CC_SHA1"].contains(node.baseName.text) {
                    add(node.baseName.text, Syntax(node))
                }
                return .skipChildren
            }
            private func add(_ name: String, _ node: Syntax) {
                findings.append(SecurityFinding(
                    line: node.startLocation(converter: converter).line,
                    message: "\(name) is not collision-resistant — use SHA256 or stronger for security hashing",
                    node: node))
            }
        }
        let v = V(converter: converter)
        v.walk(tree)
        return v.findings
    }
}
