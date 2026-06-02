import Foundation
import SwiftParser
import SwiftSyntax

/// A single `import` statement found in a file.
public struct ImportRef: Equatable {
    /// The top-level module name (for `import Foo.Bar`, this is `Foo`).
    public let module: String
    /// The full dotted path (for `import Foo.Bar`, this is `Foo.Bar`).
    public let fullPath: String
    /// 1-based line number of the import in the source file.
    public let line: Int

    public init(module: String, fullPath: String, line: Int) {
        self.module = module
        self.fullPath = fullPath
        self.line = line
    }
}

/// Walks a Swift syntax tree and collects every `import` declaration.
public final class ImportCollector: SyntaxVisitor {
    public private(set) var imports: [ImportRef] = []
    private let converter: SourceLocationConverter

    public init(converter: SourceLocationConverter) {
        self.converter = converter
        // `.sourceAccurate` ignores nodes that are not part of the parsed source
        // (e.g. nodes the parser synthesised while recovering from errors).
        super.init(viewMode: .sourceAccurate)
    }

    public override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
        let components = node.path.map { $0.name.text }
        guard let module = components.first else { return .skipChildren }

        // `startLocation(converter:)` is a stable SwiftSyntax API across recent
        // versions and avoids depending on the exact SourceLocationConverter init label.
        let location = node.startLocation(converter: converter)

        imports.append(
            ImportRef(
                module: module,
                fullPath: components.joined(separator: "."),
                line: location.line
            )
        )
        return .skipChildren
    }

    /// Convenience for parsing imports straight from a source string (used in tests).
    public static func imports(in source: String, fileName: String = "input.swift") -> [ImportRef] {
        let tree = Parser.parse(source: source)
        // If this initializer label ever errors on your toolchain, swap `fileName:`
        // for `file:` — both have existed across 6.x releases of swift-syntax.
        let converter = SourceLocationConverter(fileName: fileName, tree: tree)
        let collector = ImportCollector(converter: converter)
        collector.walk(tree)
        return collector.imports
    }
}
