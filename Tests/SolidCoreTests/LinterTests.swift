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

final class IsolatePeersTests: XCTestCase {

    private func tcaConfig() -> Configuration {
        Configuration(
            alwaysAllow: ["Foundation", "SwiftUI"],
            layers: [
                LayerRule(name: "Models",
                          paths: ["Sources/Models"],
                          modules: ["Models"],
                          allow: []),
                LayerRule(name: "Features",
                          paths: ["Sources/CounterFeature", "Sources/LoginFeature"],
                          modules: ["CounterFeature", "LoginFeature"],
                          isolatePeers: true),
                LayerRule(name: "App",
                          paths: ["Sources/AppFeature"],
                          modules: ["AppFeature"]),
            ],
            dependencyOrder: ["Models", "Features", "App"]
        )
    }

    func testPeerImportIsViolation() {
        let linter = Linter(config: tcaConfig())
        let layer = tcaConfig().layers[1]
        let imp = ImportRef(module: "LoginFeature", fullPath: "LoginFeature", line: 3)
        let v = linter.check(imp, in: layer, file: "Sources/CounterFeature/CounterFeature.swift")
        XCTAssertEqual(v?.reason, .peerImport)
        XCTAssertEqual(v?.importedModule, "LoginFeature")
        XCTAssertEqual(v?.layer, "Features")
    }

    func testInwardImportIsNotPeerViolation() {
        let linter = Linter(config: tcaConfig())
        let layer = tcaConfig().layers[1]
        let imp = ImportRef(module: "Models", fullPath: "Models", line: 2)
        XCTAssertNil(linter.check(imp, in: layer, file: "Sources/CounterFeature/CounterFeature.swift"))
    }

    func testExplicitAllowOverridesPeerViolation() {
        let config = Configuration(
            alwaysAllow: [],
            layers: [
                LayerRule(name: "Features",
                          paths: ["Sources/Features"],
                          modules: ["A", "B"],
                          allow: ["B"],
                          isolatePeers: true),
            ]
        )
        let linter = Linter(config: config)
        let imp = ImportRef(module: "B", fullPath: "B", line: 1)
        XCTAssertNil(linter.check(imp, in: config.layers[0], file: "Sources/Features/A/A.swift"))
    }

    func testIsolatePeersFalseAllowsSameLayerImport() {
        let config = Configuration(
            alwaysAllow: [],
            layers: [
                LayerRule(name: "Features",
                          paths: ["Sources/Features"],
                          modules: ["A", "B"]),
            ]
        )
        let linter = Linter(config: config)
        let imp = ImportRef(module: "B", fullPath: "B", line: 1)
        XCTAssertNil(linter.check(imp, in: config.layers[0], file: "Sources/Features/A/A.swift"))
    }
}
