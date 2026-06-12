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
        // Pass 1: dictionary literals assigned to a `let` name, keyed by that name.
        // Only `let` counts: a `var` literal can gain kSecAttrAccessible after the
        // fact (query[...] = ...) — no proof of the final contents, stay silent.
        final class DictCollector: SyntaxVisitor {
            var literals: [String: DictionaryExprSyntax] = [:]
            /// Names bound to MORE THAN ONE dictionary literal in the file.
            /// Wrapper types canonically declare `let query` in each method
            /// (save/find/delete); resolving SecItemAdd's `query` to another
            /// method's literal would be wrong. Ambiguous names are excluded.
            var collided: Set<String> = []
            override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
                guard node.bindingSpecifier.text == "let" else { return .visitChildren }
                for binding in node.bindings {
                    guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
                          let value = binding.initializer?.value else { continue }
                    if let dict = Self.unwrapDictionary(value) {
                        if literals.updateValue(dict, forKey: name) != nil { collided.insert(name) }
                    }
                }
                return .visitChildren
            }
            /// Unwrap `[...] as CFDictionary` / plain `[...]` to the literal.
            static func unwrapDictionary(_ expr: ExprSyntax) -> DictionaryExprSyntax? {
                stripAsCasts(expr).as(DictionaryExprSyntax.self)
            }
        }
        let dicts = DictCollector(viewMode: .sourceAccurate)
        dicts.walk(tree)

        // Pass 2: SecItemAdd calls whose first argument resolves to a literal.
        final class CallVisitor: SyntaxVisitor {
            var findings: [SecurityFinding] = []
            let converter: SourceLocationConverter
            let named: [String: DictionaryExprSyntax]
            let collided: Set<String>
            init(converter: SourceLocationConverter, named: [String: DictionaryExprSyntax],
                 collided: Set<String>) {
                self.converter = converter
                self.named = named
                self.collided = collided
                super.init(viewMode: .sourceAccurate)
            }
            override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
                guard node.calledExpression.trimmedDescription == "SecItemAdd",
                      let first = node.arguments.first?.expression else { return .visitChildren }
                let dict: DictionaryExprSyntax?
                if let literal = DictCollector.unwrapDictionary(first) {
                    dict = literal
                } else if let name = Self.referencedName(first), !collided.contains(name) {
                    dict = named[name]
                } else {
                    dict = nil
                }
                // kSecAttrAccessControl is mutually exclusive with
                // kSecAttrAccessible (per Apple docs, SecAccessControl carries
                // its own protection class) — adding the advised key would
                // even break the call. Never flag access-control queries.
                guard let dict, Self.hasKey(dict, "kSecClass"),
                      !Self.hasKey(dict, "kSecAttrAccessible"),
                      !Self.hasKey(dict, "kSecAttrAccessControl") else { return .visitChildren }
                findings.append(SecurityFinding(
                    line: node.startLocation(converter: converter).line,
                    message: "SecItemAdd query has no kSecAttrAccessible — the item gets the OS default protection class; set it explicitly",
                    node: Syntax(node)))
                return .visitChildren
            }
            /// `query` / `query as CFDictionary` → "query".
            static func referencedName(_ expr: ExprSyntax) -> String? {
                stripAsCasts(expr).as(DeclReferenceExprSyntax.self)?.baseName.text
            }
            static func hasKey(_ dict: DictionaryExprSyntax, _ key: String) -> Bool {
                guard case let .elements(elements) = dict.content else { return false }
                return elements.contains { $0.key.trimmedDescription.contains(key) }
            }
        }
        let calls = CallVisitor(converter: converter, named: dicts.literals,
                                collided: dicts.collided)
        calls.walk(tree)
        return calls.findings
    }
}
