import XCTest
@testable import SolidCore

final class SeverityTests: XCTestCase {
    private func writeTempYAML(_ contents: String) throws -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("solid-sev-\(UUID().uuidString).yml")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url.path
    }

    func testLayerSeverityDefaultsToError() throws {
        let path = try writeTempYAML("""
        layers:
          - name: Domain
            paths: [Sources/Domain/**]
            deny: [UIKit]
        """)
        let config = try Configuration.load(from: path)
        XCTAssertEqual(config.layers.first?.severity, .error)
    }

    func testLayerDecodesWarningSeverity() throws {
        let path = try writeTempYAML("""
        layers:
          - name: Domain
            paths: [Sources/Domain/**]
            deny: [UIKit]
            severity: warning
        """)
        let config = try Configuration.load(from: path)
        XCTAssertEqual(config.layers.first?.severity, .warning)
    }

    func testViolationCarriesLayerSeverity() {
        let layer = LayerRule(name: "Domain", paths: ["Sources/Domain/**"],
                              deny: ["UIKit"], severity: .warning)
        let linter = Linter(config: Configuration(layers: [layer]))
        let imp = ImportRef(module: "UIKit", fullPath: "UIKit", line: 3)
        let v = linter.check(imp, in: layer, file: "Sources/Domain/X.swift")
        XCTAssertEqual(v?.severity, .warning)
    }

    func testDiagnosticReflectsSeverityKeyword() {
        let warn = Violation(file: "F.swift", line: 1, importedModule: "UIKit",
                             layer: "Domain", reason: .deniedImport, severity: .warning)
        XCTAssertTrue(warn.diagnostic.contains(": warning: "), warn.diagnostic)
        let err = Violation(file: "F.swift", line: 1, importedModule: "UIKit",
                            layer: "Domain", reason: .deniedImport, severity: .error)
        XCTAssertTrue(err.diagnostic.contains(": error: "), err.diagnostic)
    }
}
