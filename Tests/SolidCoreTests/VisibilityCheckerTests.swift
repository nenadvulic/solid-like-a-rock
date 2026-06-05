import XCTest
import Yams
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

    func testVisibilitySectionDecodes() throws {
        let yaml = """
        layers:
          - name: App
            paths: [Sources/App]
        visibility:
          warnPublicInLeafModules: true
          excludeModules: [PublicSDK]
          severity: error
        """
        let config = try YAMLDecoder().decode(Configuration.self, from: yaml)
        XCTAssertEqual(config.visibility?.warnPublicInLeafModules, true)
        XCTAssertEqual(config.visibility?.excludeModules, ["PublicSDK"])
        XCTAssertEqual(config.visibility?.severity, .error)
    }

    func testVisibilitySectionDefaults() throws {
        let yaml = """
        layers:
          - name: App
            paths: [Sources/App]
        visibility:
          warnPublicInLeafModules: true
        """
        let config = try YAMLDecoder().decode(Configuration.self, from: yaml)
        XCTAssertEqual(config.visibility?.excludeModules, [])
        XCTAssertEqual(config.visibility?.severity, .warning)
        // Absent section ⇒ nil (existing configs unchanged):
        let plain = try YAMLDecoder().decode(Configuration.self, from: "layers:\n  - name: App\n    paths: [Sources/App]\n")
        XCTAssertNil(plain.visibility)
    }

    func testPublicInLeafModuleMessage() {
        let v = Violation(file: "Sources/Utils/Helper.swift", line: 3,
                          importedModule: "Helper", layer: "Utils",
                          reason: .publicInLeafModule, severity: .warning)
        XCTAssertEqual(v.message,
            "module 'Utils' is not imported by any other module, but declares public symbol 'Helper' — make it internal, or exclude the module")
        XCTAssertTrue(v.diagnostic.contains("warning:"))
    }
}
