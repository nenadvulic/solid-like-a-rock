import SwiftSyntax

/// kSecAttrAccessibleAlways(ThisDeviceOnly) is deprecated and offers no
/// device-lock protection: the item is readable even while locked.
public struct KeychainAccessibleAlwaysRule: SecurityRule {
    public static let id = "keychainAccessibleAlways"
    public static let category = "Keychain"
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
            override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
                let name = node.baseName.text
                if name == "kSecAttrAccessibleAlways" || name == "kSecAttrAccessibleAlwaysThisDeviceOnly" {
                    findings.append(SecurityFinding(
                        line: node.startLocation(converter: converter).line,
                        message: "\(name) keeps the item readable while the device is locked — use kSecAttrAccessibleWhenUnlockedThisDeviceOnly",
                        node: Syntax(node)))
                }
                return .skipChildren
            }
        }
        let v = V(converter: converter)
        v.walk(tree)
        return v.findings
    }
}
