import SwiftSyntax

/// `.deviceOwnerAuthenticationWithBiometrics` has no passcode fallback: a
/// failed Face ID locks the user out. `.deviceOwnerAuthentication` falls back
/// to the passcode. Warning — apps with their own fallback solid:ignore it.
public struct BiometryNoFallbackRule: SecurityRule {
    public static let id = "biometryNoFallback"
    public static let category = "Auth"
    public static let defaultSeverity = Severity.warning

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
                if node.declName.baseName.text == "deviceOwnerAuthenticationWithBiometrics",
                   !Self.isInsideCasePattern(node) {
                    findings.append(SecurityFinding(
                        line: node.startLocation(converter: converter).line,
                        message: "biometrics-only policy has no passcode fallback — consider .deviceOwnerAuthentication",
                        node: Syntax(node)))
                }
                return .visitChildren
            }
            /// `case .deviceOwnerAuthenticationWithBiometrics:` is provably
            /// HANDLING a policy someone else selected, not selecting one.
            /// (Plain `== .deviceOwnerAuthenticationWithBiometrics` comparisons
            /// are not provably harmless and stay flagged.)
            static func isInsideCasePattern(_ node: MemberAccessExprSyntax) -> Bool {
                var current: Syntax? = node.parent
                while let ancestor = current, !ancestor.is(CodeBlockItemSyntax.self) {
                    if ancestor.is(ExpressionPatternSyntax.self) { return true }
                    current = ancestor.parent
                }
                return false
            }
        }
        let v = V(converter: converter)
        v.walk(tree)
        return v.findings
    }
}
