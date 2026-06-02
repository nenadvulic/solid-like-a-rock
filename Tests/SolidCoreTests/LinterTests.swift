import XCTest
@testable import SolidCore

final class ImportCollectorTests: XCTestCase {
    func testCollectsSimpleImports() {
        let source = """
        import Foundation
        import UIKit

        struct Foo {}
        """
        let imports = ImportCollector.imports(in: source)
        XCTAssertEqual(imports.map(\.module), ["Foundation", "UIKit"])
        XCTAssertEqual(imports.first?.line, 1)
        XCTAssertEqual(imports.last?.line, 2)
    }

    func testCollectsSubmoduleImport() {
        let source = "import Foo.Bar\n"
        let imports = ImportCollector.imports(in: source)
        XCTAssertEqual(imports.first?.module, "Foo")
        XCTAssertEqual(imports.first?.fullPath, "Foo.Bar")
    }

    func testIgnoresImportInString() {
        // Make sure we parse the AST, not just grep for "import".
        let source = #"""
        let s = "import Secrets"
        """#
        XCTAssertTrue(ImportCollector.imports(in: source).isEmpty)
    }
}

final class LinterTests: XCTestCase {
    private func config() -> Configuration {
        Configuration(
            alwaysAllow: ["Foundation"],
            layers: [
                LayerRule(name: "Domain", paths: ["Sources/Domain"], allow: ["Foundation"]),
                LayerRule(name: "Presentation", paths: ["Sources/Presentation"], deny: ["Data"]),
            ]
        )
    }

    func testWhitelistViolation() {
        let linter = Linter(config: config())
        let layer = config().layers[0] // Domain
        let imp = ImportRef(module: "UIKit", fullPath: "UIKit", line: 3)
        let v = linter.check(imp, in: layer, file: "Sources/Domain/Entity.swift")
        XCTAssertEqual(v?.reason, .notAllowedImport)
    }

    func testWhitelistAllowsListedModule() {
        let linter = Linter(config: config())
        let layer = config().layers[0]
        let imp = ImportRef(module: "Foundation", fullPath: "Foundation", line: 1)
        XCTAssertNil(linter.check(imp, in: layer, file: "Sources/Domain/Entity.swift"))
    }

    func testBlacklistViolation() {
        let linter = Linter(config: config())
        let layer = config().layers[1] // Presentation
        let imp = ImportRef(module: "Data", fullPath: "Data", line: 2)
        let v = linter.check(imp, in: layer, file: "Sources/Presentation/View.swift")
        XCTAssertEqual(v?.reason, .deniedImport)
    }

    func testLayerMatchingByPath() {
        let linter = Linter(config: config())
        XCTAssertEqual(linter.layer(for: "/proj/Sources/Domain/Entity.swift")?.name, "Domain")
        XCTAssertNil(linter.layer(for: "/proj/Sources/Misc/Helper.swift"))
    }
}
