import XCTest
@testable import SolidCore

final class VisibilityCheckerTests: XCTestCase {
    private let fm = FileManager.default

    /// root/Sources/<module>/<file>.swift — files given as full source text.
    @discardableResult
    private func makeProject(_ modules: [String: [String: String]]) throws -> String {
        let root = fm.temporaryDirectory.appendingPathComponent("solid-vis-\(UUID().uuidString)")
        for (module, files) in modules {
            let dir = root.appendingPathComponent("Sources/\(module)")
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            for (file, source) in files {
                try source.write(to: dir.appendingPathComponent("\(file).swift"),
                                 atomically: true, encoding: .utf8)
            }
        }
        addTeardownBlock { try? self.fm.removeItem(at: root) }
        return root.path
    }

    func testLeafModulesAreModulesNoOneImports() throws {
        let root = try makeProject([
            "A": ["File": "import B\npublic struct AThing {}\n"],
            "B": ["File": "struct BThing {}\n"],
            "C": ["File": "public enum CThing {}\n"],
        ])
        let graph = ModuleGraph.build(root: root)
        XCTAssertEqual(graph.leafModules.map(\.name).sorted(), ["A", "C"])
    }
}
