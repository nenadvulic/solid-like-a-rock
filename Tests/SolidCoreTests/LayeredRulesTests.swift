import XCTest
@testable import SolidCore

/// Decoding + semantics for the v0.1.5 layered model: a layer owns one or more
/// modules, and `dependencyOrder` derives the "no outward dependency" rule.
final class LayeredRulesTests: XCTestCase {
    private func writeTempYAML(_ contents: String) throws -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("solid-layered-\(UUID().uuidString).yml")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url.path
    }

    // MARK: Decoding

    func testLayerDecodesExplicitModules() throws {
        let path = try writeTempYAML("""
        layers:
          - name: Domain
            modules: [DomainModels, DomainServices]
            paths: [Sources/Domain/**]
        """)
        let config = try Configuration.load(from: path)
        XCTAssertEqual(config.layers.first?.modules, ["DomainModels", "DomainServices"])
    }

    func testLayerModulesDefaultToName() throws {
        let path = try writeTempYAML("""
        layers:
          - name: Domain
            paths: [Sources/Domain/**]
        """)
        let config = try Configuration.load(from: path)
        // When `modules` is omitted, the layer owns the single module named after it.
        XCTAssertEqual(config.layers.first?.modules, ["Domain"])
    }

    func testDecodesDependencyOrder() throws {
        let path = try writeTempYAML("""
        dependencyOrder: [Domain, Application, Infrastructure, Presentation]
        layers:
          - name: Domain
            paths: [Sources/Domain/**]
        """)
        let config = try Configuration.load(from: path)
        XCTAssertEqual(config.dependencyOrder, ["Domain", "Application", "Infrastructure", "Presentation"])
    }

    func testDependencyOrderDefaultsToEmpty() throws {
        let path = try writeTempYAML("""
        layers:
          - name: Domain
            paths: [Sources/Domain/**]
        """)
        let config = try Configuration.load(from: path)
        XCTAssertEqual(config.dependencyOrder, [])
    }

    // MARK: dependencyOrder semantics

    /// Domain (inner) ── Application ── Presentation (outer).
    private func orderedConfig(domainAllow: [String]? = nil,
                               presentationDeny: [String]? = nil) -> Configuration {
        Configuration(
            alwaysAllow: ["Foundation"],
            layers: [
                LayerRule(name: "Domain", paths: ["Sources/Domain/**"],
                          modules: ["DomainCore", "DomainServices"], allow: domainAllow),
                LayerRule(name: "Application", paths: ["Sources/App/**"], modules: ["AppCore"]),
                LayerRule(name: "Presentation", paths: ["Sources/UI/**"],
                          modules: ["PresUI"], deny: presentationDeny),
            ],
            dependencyOrder: ["Domain", "Application", "Presentation"]
        )
    }

    func testOutwardDependencyIsViolation() {
        let cfg = orderedConfig()
        let linter = Linter(config: cfg)
        let imp = ImportRef(module: "PresUI", fullPath: "PresUI", line: 4)
        let v = linter.check(imp, in: cfg.layers[0], file: "Sources/Domain/Thing.swift")
        XCTAssertEqual(v?.reason, .outwardDependency)
        XCTAssertEqual(v?.targetLayer, "Presentation")
    }

    func testInwardDependencyIsAllowed() {
        let cfg = orderedConfig()
        let linter = Linter(config: cfg)
        let imp = ImportRef(module: "DomainCore", fullPath: "DomainCore", line: 4)
        XCTAssertNil(linter.check(imp, in: cfg.layers[2], file: "Sources/UI/View.swift"))
    }

    func testIntraLayerDependencyIsAllowed() {
        let cfg = orderedConfig()
        let linter = Linter(config: cfg)
        // DomainServices and DomainCore both belong to Domain.
        let imp = ImportRef(module: "DomainServices", fullPath: "DomainServices", line: 4)
        XCTAssertNil(linter.check(imp, in: cfg.layers[0], file: "Sources/Domain/Thing.swift"))
    }

    func testUnknownExternalModuleIsAllowed() {
        let cfg = orderedConfig()
        let linter = Linter(config: cfg)
        let imp = ImportRef(module: "UIKit", fullPath: "UIKit", line: 4)
        XCTAssertNil(linter.check(imp, in: cfg.layers[0], file: "Sources/Domain/Thing.swift"))
    }

    func testExplicitDenyOverridesAllowedInwardDependency() {
        // Presentation→Domain is normally fine, but an explicit deny forces it.
        let cfg = orderedConfig(presentationDeny: ["DomainCore"])
        let linter = Linter(config: cfg)
        let imp = ImportRef(module: "DomainCore", fullPath: "DomainCore", line: 4)
        let v = linter.check(imp, in: cfg.layers[2], file: "Sources/UI/View.swift")
        XCTAssertEqual(v?.reason, .deniedImport)
    }

    func testExplicitAllowExemptsOutwardDependency() {
        // Domain→Presentation is normally a violation, but an explicit allow exempts it.
        let cfg = orderedConfig(domainAllow: ["PresUI"])
        let linter = Linter(config: cfg)
        let imp = ImportRef(module: "PresUI", fullPath: "PresUI", line: 4)
        XCTAssertNil(linter.check(imp, in: cfg.layers[0], file: "Sources/Domain/Thing.swift"))
    }

    // MARK: Validation

    func testValidatePassesOnValidConfig() throws {
        XCTAssertNoThrow(try orderedConfig().validate())
    }

    func testValidateThrowsWhenModuleClaimedByTwoLayers() {
        let cfg = Configuration(layers: [
            LayerRule(name: "A", paths: ["a/**"], modules: ["Shared", "AOnly"]),
            LayerRule(name: "B", paths: ["b/**"], modules: ["Shared", "BOnly"]),
        ])
        XCTAssertThrowsError(try cfg.validate()) { error in
            XCTAssertEqual(error as? ConfigurationError, .duplicateModule("Shared", ["A", "B"]))
        }
    }

    func testValidateThrowsOnUnknownLayerInDependencyOrder() {
        let cfg = Configuration(
            layers: [LayerRule(name: "Domain", paths: ["d/**"])],
            dependencyOrder: ["Domain", "Ghost"]
        )
        XCTAssertThrowsError(try cfg.validate()) { error in
            XCTAssertEqual(error as? ConfigurationError, .unknownLayerInOrder("Ghost"))
        }
    }
}
