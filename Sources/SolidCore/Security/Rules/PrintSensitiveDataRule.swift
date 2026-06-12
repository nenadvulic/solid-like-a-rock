import SwiftSyntax

/// print/NSLog/debugPrint/dump ship to the console in release builds and end
/// up in sysdiagnoses; a sensitive identifier there is a leak. Warning —
/// name-based heuristic.
public struct PrintSensitiveDataRule: SecurityRule {
    public static let id = "printSensitiveData"
    public static let category = "Logging"
    public static let defaultSeverity = Severity.warning

    static let sinkNames: Set<String> = ["print", "debugPrint", "NSLog", "dump"]
    /// PII + secret words combined: both leak in a log line.
    static let words = Array(Set(piiNameWords + secretNameWords))

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
            override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
                guard let callee = node.calledExpression.as(DeclReferenceExprSyntax.self),
                      PrintSensitiveDataRule.sinkNames.contains(callee.baseName.text)
                else { return .visitChildren }
                if let name = Self.firstSensitiveIdentifier(in: node) {
                    findings.append(SecurityFinding(
                        line: node.startLocation(converter: converter).line,
                        message: "'\(name)' is written to the console via \(callee.baseName.text)() — remove it or use os_log with privacy redaction",
                        node: Syntax(node)))
                }
                return .visitChildren
            }
            /// Direct identifier args and identifiers inside interpolations.
            static func firstSensitiveIdentifier(in call: FunctionCallExprSyntax) -> String? {
                final class Finder: SyntaxVisitor {
                    var match: String?
                    override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
                        if match == nil,
                           matchesSensitiveName(node.baseName.text, words: PrintSensitiveDataRule.words) {
                            match = node.baseName.text
                        }
                        return .skipChildren
                    }
                }
                let finder = Finder(viewMode: .sourceAccurate)
                for arg in call.arguments { finder.walk(arg.expression) }
                return finder.match
            }
        }
        let v = V(converter: converter)
        v.walk(tree)
        return v.findings
    }
}
