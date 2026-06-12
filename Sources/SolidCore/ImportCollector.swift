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
    /// If the import carries a `// solid:ignore <reason>` directive (same line or
    /// the line above), the captured reason. `nil` means no suppression.
    public let ignoreReason: String?

    public init(module: String, fullPath: String, line: Int, ignoreReason: String? = nil) {
        self.module = module
        self.fullPath = fullPath
        self.line = line
        self.ignoreReason = ignoreReason
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

        // A `// solid:ignore <reason>` may sit on the same line (trailing trivia)
        // or just above the import (leading trivia).
        let reason = Self.ignoreReason(in: node.leadingTrivia)
            ?? Self.ignoreReason(in: node.trailingTrivia)

        imports.append(
            ImportRef(
                module: module,
                fullPath: components.joined(separator: "."),
                line: location.line,
                ignoreReason: reason
            )
        )
        return .skipChildren
    }

    /// Extract the reason from a `solid:ignore <reason>` directive found in any
    /// comment of the given trivia. Returns `nil` if absent or if no (non-empty)
    /// reason follows the directive — the reason is mandatory.
    /// Delegates to the shared helper in `TriviaIgnore.swift` so security rules
    /// honor the exact same directive syntax.
    static func ignoreReason(in trivia: Trivia) -> String? {
        solidIgnoreReason(in: trivia)
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
