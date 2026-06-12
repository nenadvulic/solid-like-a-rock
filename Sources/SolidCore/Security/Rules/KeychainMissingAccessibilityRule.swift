import SwiftSyntax

/// A SecItemAdd query whose dictionary literal (inline, or assigned to the
/// passed variable in the same file) contains kSecClass but no
/// kSecAttrAccessible: the item silently gets the OS default. Dictionaries
/// built dynamically or out of file are NOT flagged — no proof, no noise.
public struct KeychainMissingAccessibilityRule: SecurityRule {
    public static let id = "keychainMissingAccessibility"
    public static let category = "Keychain"
    public static let defaultSeverity = Severity.error

    public init() {}

    public func check(_ tree: SourceFileSyntax, file: String,
                      converter: SourceLocationConverter) -> [SecurityFinding] {
        // Pass 1: dictionary literals assigned to a name, keyed by that name.
        final class DictCollector: SyntaxVisitor {
            var literals: [String: DictionaryExprSyntax] = [:]
            override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
                for binding in node.bindings {
                    guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
                          let value = binding.initializer?.value else { continue }
                    if let dict = Self.unwrapDictionary(value) { literals[name] = dict }
                }
                return .visitChildren
            }
            /// Unwrap `[...] as CFDictionary` / plain `[...]` to the literal.
            /// Note: `expr as Type` is parsed as a SequenceExprSyntax with three
            /// elements — [expr, unresolvedAsExpr, typeExpr] — not as AsExprSyntax.
            static func unwrapDictionary(_ expr: ExprSyntax) -> DictionaryExprSyntax? {
                if let dict = expr.as(DictionaryExprSyntax.self) { return dict }
                if let seq = expr.as(SequenceExprSyntax.self),
                   seq.elements.count == 3,
                   seq.elements[seq.elements.index(seq.elements.startIndex, offsetBy: 1)]
                       ._syntaxNode.kind == .unresolvedAsExpr {
                    return unwrapDictionary(ExprSyntax(seq.elements[seq.elements.startIndex]))
                }
                return nil
            }
        }
        let dicts = DictCollector(viewMode: .sourceAccurate)
        dicts.walk(tree)

        // Pass 2: SecItemAdd calls whose first argument resolves to a literal.
        final class CallVisitor: SyntaxVisitor {
            var findings: [SecurityFinding] = []
            let converter: SourceLocationConverter
            let named: [String: DictionaryExprSyntax]
            init(converter: SourceLocationConverter, named: [String: DictionaryExprSyntax]) {
                self.converter = converter
                self.named = named
                super.init(viewMode: .sourceAccurate)
            }
            override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
                guard node.calledExpression.trimmedDescription == "SecItemAdd",
                      let first = node.arguments.first?.expression else { return .visitChildren }
                let dict: DictionaryExprSyntax?
                if let literal = DictCollector.unwrapDictionary(first) {
                    dict = literal
                } else if let name = Self.referencedName(first) {
                    dict = named[name]
                } else {
                    dict = nil
                }
                guard let dict, Self.hasKey(dict, "kSecClass"),
                      !Self.hasKey(dict, "kSecAttrAccessible") else { return .visitChildren }
                findings.append(SecurityFinding(
                    line: node.startLocation(converter: converter).line,
                    message: "SecItemAdd query has no kSecAttrAccessible — the item gets the OS default protection class; set it explicitly",
                    node: Syntax(node)))
                return .visitChildren
            }
            /// `query` / `query as CFDictionary` → "query".
            /// Handles the SequenceExprSyntax form of `expr as Type`.
            static func referencedName(_ expr: ExprSyntax) -> String? {
                if let ref = expr.as(DeclReferenceExprSyntax.self) { return ref.baseName.text }
                if let seq = expr.as(SequenceExprSyntax.self),
                   seq.elements.count == 3,
                   seq.elements[seq.elements.index(seq.elements.startIndex, offsetBy: 1)]
                       ._syntaxNode.kind == .unresolvedAsExpr {
                    return referencedName(ExprSyntax(seq.elements[seq.elements.startIndex]))
                }
                return nil
            }
            static func hasKey(_ dict: DictionaryExprSyntax, _ key: String) -> Bool {
                guard case let .elements(elements) = dict.content else { return false }
                return elements.contains { $0.key.trimmedDescription.contains(key) }
            }
        }
        let calls = CallVisitor(converter: converter, named: dicts.literals)
        calls.walk(tree)
        return calls.findings
    }
}
