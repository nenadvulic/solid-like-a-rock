import SwiftSyntax

/// A cleartext-HTTP URL literal in code, excluding loopback/dev hosts.
/// Complements the Info.plist ATS check. Warning — dev tooling and tests
/// legitimately reference http endpoints.
public struct HttpURLLiteralRule: SecurityRule {
    public static let id = "httpURLLiteral"
    public static let category = "Network"
    public static let defaultSeverity = Severity.warning

    static let exemptHosts = ["localhost", "127.0.0.1", "::1"]

    /// XML namespace / DTD authority hosts — these strings are opaque
    /// identifiers, never fetched as network URLs. Allowlisting is the
    /// provable cheap version of "never fetched"; extending is safe because
    /// false-negatives (missed real http requests) are more acceptable than
    /// false-positives that erode trust in the tool.
    static let namespaceHosts: Set<String> = [
        "www.w3.org",
        "schemas.android.com",
        "schemas.microsoft.com",
        "schemas.xmlsoap.org",
        "xmlns.com",
        "purl.org",
        "ns.adobe.com",
        "www.apple.com",
    ]

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
                let afterScheme = String(value.dropFirst("http://".count))
                let host = afterScheme.split(separator: "/").first.map(String.init) ?? ""
                // Strip port to get the bare hostname.
                let bare = host.split(separator: ":").first.map(String.init) ?? host

                // Bare empty string — this is the "http://" prefix literal used
                // in idioms like url.hasPrefix("http://"). Not a fetchable URL.
                if bare.isEmpty { return .skipChildren }

                if HttpURLLiteralRule.exemptHosts.contains(bare) || bare.hasSuffix(".local") {
                    return .skipChildren
                }

                // XML namespace / DTD authority — opaque identifier, never fetched.
                if HttpURLLiteralRule.namespaceHosts.contains(bare) { return .skipChildren }

                // Path ends in .dtd — DTD system identifier, not a live endpoint.
                let path = afterScheme.split(separator: "/", omittingEmptySubsequences: false)
                    .dropFirst().joined(separator: "/")
                if path.hasSuffix(".dtd") { return .skipChildren }

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
