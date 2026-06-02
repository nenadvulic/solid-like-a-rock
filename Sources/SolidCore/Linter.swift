import Foundation
import SwiftParser
import SwiftSyntax

/// Applies a `Configuration` to a set of Swift files and reports violations.
public final class Linter {
    private let config: Configuration

    public init(config: Configuration) {
        self.config = config
    }

    /// Lint a list of `.swift` file paths. Files that don't match any layer are skipped.
    public func lint(files: [String]) throws -> [Violation] {
        var violations: [Violation] = []
        for file in files {
            guard let layer = layer(for: file) else { continue }
            let source = try String(contentsOfFile: file, encoding: .utf8)
            let tree = Parser.parse(source: source)
            let converter = SourceLocationConverter(fileName: file, tree: tree)
            let collector = ImportCollector(converter: converter)
            collector.walk(tree)
            for imp in collector.imports {
                if let violation = check(imp, in: layer, file: file) {
                    violations.append(violation)
                }
            }
        }
        return violations
    }

    /// Find the first layer whose configured paths match this file path.
    ///
    /// Each `paths` entry is a glob (see `globMatch`). A bare directory fragment
    /// like `Sources/Domain` (no wildcard) is treated as "this directory and
    /// everything under it" — matching `Sources/Domain/...` but, thanks to
    /// component-boundary alignment, never the sibling `Sources/DomainHelpers`.
    func layer(for file: String) -> LayerRule? {
        config.layers.first { rule in
            rule.paths.contains { pathMatches(file, pattern: $0) }
        }
    }

    /// A file matches a path pattern if the glob matches it directly, or if the
    /// pattern names a containing directory (`pattern/**`).
    private func pathMatches(_ file: String, pattern: String) -> Bool {
        globMatch(file, pattern: pattern) || globMatch(file, pattern: pattern + "/**")
    }

    /// Evaluate a single import against a layer's rules.
    ///
    /// Evaluation order (see README): alwaysAllow → same layer → explicit
    /// deny/allow exceptions → dependencyOrder derivation → external default.
    func check(_ imp: ImportRef, in layer: LayerRule, file: String) -> Violation? {
        let module = imp.module

        // 1. System frameworks etc. are always fine.
        if config.alwaysAllow.contains(module) { return nil }

        // 2. A module that belongs to this same layer is always fine (intra-layer).
        if layer.modules.contains(module) { return nil }

        // 3. Explicit exceptions take precedence over any derived rule.
        //    deny FORCES a violation; allow EXEMPTS the import.
        if let deny = layer.deny, deny.contains(module) {
            return Violation(file: file, line: imp.line, importedModule: module,
                             layer: layer.name, reason: .deniedImport)
        }
        if let allow = layer.allow, allow.contains(module) { return nil }

        // 4. Derived rule from dependencyOrder: importing a more-outer layer is
        //    an outward dependency and therefore a violation.
        if !config.dependencyOrder.isEmpty,
           let here = config.dependencyOrder.firstIndex(of: layer.name),
           let targetLayer = self.layer(owning: module),
           let there = config.dependencyOrder.firstIndex(of: targetLayer.name),
           there > here {
            return Violation(file: file, line: imp.line, importedModule: module,
                             layer: layer.name, reason: .outwardDependency,
                             targetLayer: targetLayer.name)
        }

        // 5. Whitelist mode (v0.1.0): with an `allow` list, anything not on it is
        //    a violation. Only applies when allow is set and didn't match above.
        if let allow = layer.allow, !allow.contains(module) {
            return Violation(file: file, line: imp.line, importedModule: module,
                             layer: layer.name, reason: .notAllowedImport)
        }

        // 6. Unknown / external module with no rule against it: allowed.
        return nil
    }

    /// The layer that declares `module` among its `modules`, if any.
    func layer(owning module: String) -> LayerRule? {
        config.layers.first { $0.modules.contains(module) }
    }
}

/// Recursively collect every `.swift` file under a directory.
///
/// Any file whose full path contains one of the `excluding` fragments is
/// skipped — use it to keep dependencies and build artefacts (`.build`, `Pods`,
/// `checkouts`, …) out of the scan.
public func swiftFiles(under directory: String, excluding: [String] = []) -> [String] {
    let fileManager = FileManager.default
    guard let enumerator = fileManager.enumerator(atPath: directory) else { return [] }
    var result: [String] = []
    for case let relativePath as String in enumerator where relativePath.hasSuffix(".swift") {
        let fullPath = (directory as NSString).appendingPathComponent(relativePath)
        if excluding.contains(where: { fullPath.contains($0) }) { continue }
        result.append(fullPath)
    }
    return result
}
