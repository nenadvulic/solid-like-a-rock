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
    func layer(for file: String) -> LayerRule? {
        let normalized = file.replacingOccurrences(of: "\\", with: "/")
        return config.layers.first { rule in
            rule.paths.contains { normalized.contains($0) }
        }
    }

    /// Evaluate a single import against a layer's rules.
    func check(_ imp: ImportRef, in layer: LayerRule, file: String) -> Violation? {
        let module = imp.module

        // System frameworks etc. are always fine.
        if config.alwaysAllow.contains(module) { return nil }
        // A layer can always import a module that shares its own name.
        if module == layer.name { return nil }

        // Blacklist takes priority.
        if let deny = layer.deny, deny.contains(module) {
            return Violation(file: file, line: imp.line, importedModule: module,
                             layer: layer.name, reason: .deniedImport)
        }

        // Whitelist mode: anything not explicitly allowed is a violation.
        if let allow = layer.allow, !allow.contains(module) {
            return Violation(file: file, line: imp.line, importedModule: module,
                             layer: layer.name, reason: .notAllowedImport)
        }

        return nil
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
