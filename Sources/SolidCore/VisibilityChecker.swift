import Foundation
import SwiftParser
import SwiftSyntax

/// Opt-in rule: top-level `public`/`open` declarations in leaf modules
/// (modules no other local module imports) should be `internal` — unless the
/// module is a product for external consumers (`excludeModules`) or an
/// executable (detected via `main.swift` / a top-level `@main` declaration).
public struct VisibilityChecker {
    private let rules: VisibilityRules

    public init(rules: VisibilityRules) {
        self.rules = rules
    }

    /// `roots` are the paths passed to `lint`; each is tried with the same
    /// layout detection as `init`. Roots with no discoverable modules are
    /// skipped silently (the rule simply doesn't apply there).
    public func check(roots: [String], excluding: [String] = []) -> [Violation] {
        guard rules.warnPublicInLeafModules else { return [] }
        var violations: [Violation] = []
        for root in roots {
            let graph = ModuleGraph.build(root: root)
            for module in graph.leafModules where !rules.excludeModules.contains(module.name) {
                let dir = (root as NSString).appendingPathComponent(module.pathPrefix)
                let files = swiftFiles(under: dir, excluding: excluding + ["/Tests/"])

                // Executable modules are leaves by nature — skip them.
                if files.contains(where: { ($0 as NSString).lastPathComponent == "main.swift" }) { continue }

                var moduleViolations: [Violation] = []
                var isExecutable = false
                for file in files {
                    guard let source = try? String(contentsOfFile: file, encoding: .utf8) else { continue }
                    let tree = Parser.parse(source: source)
                    if Self.hasTopLevelMain(in: tree) { isExecutable = true; break }
                    let converter = SourceLocationConverter(fileName: file, tree: tree)
                    for decl in Self.topLevelPublicDecls(in: tree) {
                        moduleViolations.append(.publicInLeafModule(
                            module: module.name,
                            symbol: decl.name,
                            file: file,
                            line: decl.node.startLocation(converter: converter).line,
                            severity: rules.severity))
                    }
                }
                if !isExecutable { violations += moduleViolations }
            }
        }
        return violations
    }

    // MARK: - Top-level declaration scan

    struct PublicDecl {
        let name: String
        let node: Syntax
    }

    /// Walk only the source file's direct children — members stay untouched.
    static func topLevelPublicDecls(in tree: SourceFileSyntax) -> [PublicDecl] {
        var result: [PublicDecl] = []
        for item in tree.statements {
            guard let decl = item.item.as(DeclSyntax.self) else { continue }
            // A variable decl can declare several names at once (`let a = 1, b = 2`);
            // flag each binding so none is silently missed.
            if let d = decl.as(VariableDeclSyntax.self) {
                guard d.modifiers.contains(where: { ["public", "open"].contains($0.name.text) })
                else { continue }
                for binding in d.bindings {
                    result.append(PublicDecl(name: binding.pattern.trimmedDescription,
                                             node: Syntax(binding)))
                }
                continue
            }
            guard let info = declInfo(decl), info.isPublic else { continue }
            result.append(PublicDecl(name: info.name, node: Syntax(decl)))
        }
        return result
    }

    /// `true` if any top-level declaration carries `@main` (public or not).
    static func hasTopLevelMain(in tree: SourceFileSyntax) -> Bool {
        tree.statements.contains { item in
            guard let decl = item.item.as(DeclSyntax.self) else { return false }
            return declInfo(decl)?.hasMain ?? false
        }
    }

    private static func declInfo(_ decl: DeclSyntax)
        -> (name: String, isPublic: Bool, hasMain: Bool)? {
        func flags(_ mods: DeclModifierListSyntax, _ attrs: AttributeListSyntax)
            -> (isPublic: Bool, hasMain: Bool) {
            let isPublic = mods.contains { ["public", "open"].contains($0.name.text) }
            let hasMain = attrs.contains {
                $0.as(AttributeSyntax.self)?.attributeName.trimmedDescription == "main"
            }
            return (isPublic, hasMain)
        }
        if let d = decl.as(ClassDeclSyntax.self) {
            let f = flags(d.modifiers, d.attributes); return (d.name.text, f.isPublic, f.hasMain)
        }
        if let d = decl.as(StructDeclSyntax.self) {
            let f = flags(d.modifiers, d.attributes); return (d.name.text, f.isPublic, f.hasMain)
        }
        if let d = decl.as(EnumDeclSyntax.self) {
            let f = flags(d.modifiers, d.attributes); return (d.name.text, f.isPublic, f.hasMain)
        }
        if let d = decl.as(ActorDeclSyntax.self) {
            let f = flags(d.modifiers, d.attributes); return (d.name.text, f.isPublic, f.hasMain)
        }
        if let d = decl.as(ProtocolDeclSyntax.self) {
            let f = flags(d.modifiers, d.attributes); return (d.name.text, f.isPublic, f.hasMain)
        }
        if let d = decl.as(FunctionDeclSyntax.self) {
            let f = flags(d.modifiers, d.attributes); return (d.name.text, f.isPublic, f.hasMain)
        }
        if let d = decl.as(TypeAliasDeclSyntax.self) {
            let f = flags(d.modifiers, d.attributes); return (d.name.text, f.isPublic, f.hasMain)
        }
        if let d = decl.as(VariableDeclSyntax.self) {
            let f = flags(d.modifiers, d.attributes)
            let name = d.bindings.first?.pattern.trimmedDescription ?? "_"
            return (name, f.isPublic, f.hasMain)
        }
        if let d = decl.as(ExtensionDeclSyntax.self) {
            let f = flags(d.modifiers, d.attributes)
            return ("extension \(d.extendedType.trimmedDescription)", f.isPublic, f.hasMain)
        }
        return nil
    }
}
