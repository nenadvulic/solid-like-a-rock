import SwiftSyntax

/// A cleartext-HTTP URL literal in code, excluding loopback/dev hosts.
/// Complements the Info.plist ATS check. Warning — dev tooling and tests
/// legitimately reference http endpoints.
public struct HttpURLLiteralRule: SecurityRule {
    public static let id = "httpURLLiteral"
    public static let category = "Network"
    public static let defaultSeverity = Severity.warning

    static let exemptHosts = ["localhost", "127.0.0.1", "::1"]

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
            override func visit(_ node: StringLiteralExprSyntax) -> SyntaxVisitorContinueKind {
                guard let value = plainTextValue(of: node),
                      value.hasPrefix("http://") else { return .skipChildren }
                let host = String(value.dropFirst("http://".count))
                    .split(separator: "/").first.map(String.init) ?? ""
                let bare = host.split(separator: ":").first.map(String.init) ?? host
                if HttpURLLiteralRule.exemptHosts.contains(bare) || bare.hasSuffix(".local") {
                    return .skipChildren
                }
                findings.append(SecurityFinding(
                    line: node.startLocation(converter: converter).line,
                    message: "cleartext HTTP URL '\(value)' — use https:// (ATS blocks this by default)",
                    node: Syntax(node)))
                return .skipChildren
            }
        }
        let v = V(converter: converter)
        v.walk(tree)
        return v.findings
    }
}
