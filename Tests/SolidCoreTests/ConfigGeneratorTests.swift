import XCTest
@testable import SolidCore

final class ConfigGeneratorTests: XCTestCase {
    private let fm = FileManager.default

    /// Build a temporary single-package project: `root/Sources/<module>/<file>.swift`
    /// with the given import lines.
    private func makeProject(_ modules: [String: [String: [String]]]) throws -> String {
        // modules: [moduleName: [fileName: [importedModuleNames]]]
        let root = fm.temporaryDirectory.appendingPathComponent("solid-init-\(UUID().uuidString)")
        for (module, files) in modules {
            let dir = root.appendingPathComponent("Sources/\(module)")
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            for (file, imports) in files {
                let body = imports.map { "import \($0)" }.joined(separator: "\n") + "\npublic let x = 1\n"
                try body.write(to: dir.appendingPathComponent("\(file).swift"), atomically: true, encoding: .utf8)
            }
        }
        addTeardownBlock { try? self.fm.removeItem(at: root) }
        return root.path
    }

    // MARK: Discovery + freeze

    func testFreezeDeniesOnlyUnimportedLocalModules() throws {
        // A imports B (+ Foundation). Locals: A, B, C.
        let root = try makeProject([
            "A": ["File": ["Foundation", "B"]],
            "B": ["File": ["Foundation"]],
            "C": ["File": ["Foundation"]],
        ])
        let yaml = try ConfigGenerator(root: root, packagesDir: nil).generate(mode: .freeze)
        let config = try YAMLDecoderShim.decode(yaml)

        let a = try XCTUnwrap(config.layers.first { $0.name == "A" })
        // A imports B → only C is denied (B allowed because already imported; not self).
        XCTAssertEqual(a.deny, ["C"])
        // B imports no local module → denies A and C.
        let b = try XCTUnwrap(config.layers.first { $0.name == "B" })
        XCTAssertEqual(b.deny, ["A", "C"])
    }

    func testFreezeOmitsDenyWhenEmpty() throws {
        // Single module imports everything local → nothing to deny.
        let root = try makeProject([
            "A": ["File": ["B"]],
            "B": ["File": ["A"]],
        ])
        let yaml = try ConfigGenerator(root: root, packagesDir: nil).generate(mode: .freeze)
        let config = try YAMLDecoderShim.decode(yaml)
        XCTAssertNil(config.layers.first { $0.name == "A" }?.deny)
    }

    func testGeneratedYAMLIsValidAndDeterministic() throws {
        let root = try makeProject([
            "A": ["File": ["B"]],
            "B": ["File": ["Foundation"]],
            "C": ["File": ["A", "B"]],
        ])
        let gen = ConfigGenerator(root: root, packagesDir: nil)
        let first = try gen.generate(mode: .freeze)
        let second = try gen.generate(mode: .freeze)
        XCTAssertEqual(first, second, "two runs must be byte-identical")
        XCTAssertNoThrow(try YAMLDecoderShim.decode(first))
    }

    func testPathsEndWithSlashToAvoidPrefixCollisions() throws {
        let root = try makeProject([
            "Account": ["File": ["Foundation"]],
            "AppAccount": ["File": ["Foundation"]],
        ])
        let yaml = try ConfigGenerator(root: root, packagesDir: nil).generate(mode: .freeze)
        XCTAssertTrue(yaml.contains("Sources/Account/\n") || yaml.contains("Sources/Account/"))
        let config = try YAMLDecoderShim.decode(yaml)
        XCTAssertTrue(config.layers.allSatisfy { $0.paths.allSatisfy { $0.hasSuffix("/") } })
    }

    func testNoModulesThrows() throws {
        let empty = fm.temporaryDirectory.appendingPathComponent("solid-empty-\(UUID().uuidString)")
        try fm.createDirectory(at: empty, withIntermediateDirectories: true)
        addTeardownBlock { try? self.fm.removeItem(at: empty) }
        XCTAssertThrowsError(try ConfigGenerator(root: empty.path, packagesDir: nil).generate(mode: .freeze))
    }

    // MARK: Integration on the bundled fixture

    func testFreezeOnCleanArchSampleProducesZeroViolations() throws {
        let root = try XCTUnwrap(
            Bundle.module.url(forResource: "Fixtures/CleanArchSample", withExtension: nil)?.path
        )
        let yaml = try ConfigGenerator(root: root, packagesDir: nil).generate(mode: .freeze)
        let config = try YAMLDecoderShim.decode(yaml)
        let linter = Linter(config: config)
        let files = swiftFiles(under: root + "/Sources", excluding: ["/Tests/"])

        // Files must actually bind to a layer (guards against a false zero from a
        // path that matches nothing).
        let domainFile = try XCTUnwrap(files.first { $0.contains("/Domain/") })
        XCTAssertNotNil(linter.layer(for: domainFile))

        // Freezing the status quo yields zero violations.
        XCTAssertTrue(try linter.lint(files: files).isEmpty)
    }

    // MARK: Layered mode

    func testLayeredDeniesOnlyOutwardModules() throws {
        // A (rank 0) ← B (rank 1) ← C (rank 2):  C imports B, B imports A.
        let root = try makeProject([
            "A": ["File": ["Foundation"]],
            "B": ["File": ["A"]],
            "C": ["File": ["B"]],
        ])
        let yaml = try ConfigGenerator(root: root, packagesDir: nil).generate(mode: .layered)
        let config = try YAMLDecoderShim.decode(yaml)

        // A is innermost (rank 0): denies more-outer B and C.
        XCTAssertEqual(config.layers.first { $0.name == "A" }?.deny, ["B", "C"])
        // C is outermost (max rank): denies nothing.
        XCTAssertNil(config.layers.first { $0.name == "C" }?.deny)
    }

    // MARK: TCA detection

    func testTCADetectsFeatureModulesByNaming() throws {
        // *Feature modules → Features layer with isolatePeers.
        let root = try makeProject([
            "CounterFeature": ["CounterFeature": ["Foundation", "Models"]],
            "LoginFeature":   ["LoginFeature":   ["Foundation", "Models"]],
            "Models":         ["User":           ["Foundation"]],
        ])
        let yaml = try ConfigGenerator(root: root, packagesDir: nil).generate(mode: .tca)
        let config = try YAMLDecoderShim.decode(yaml)

        let features = try XCTUnwrap(config.layers.first { $0.name == "Features" })
        XCTAssertTrue(features.isolatePeers, "Features layer must have isolatePeers: true")
        XCTAssertTrue(features.modules.contains("CounterFeature"))
        XCTAssertTrue(features.modules.contains("LoginFeature"))

        let models = try XCTUnwrap(config.layers.first { $0.name == "Models" })
        XCTAssertFalse(models.isolatePeers)

        // dependencyOrder must place Models before Features.
        let order = config.dependencyOrder
        let modelsIdx   = try XCTUnwrap(order.firstIndex(of: "Models"))
        let featuresIdx = try XCTUnwrap(order.firstIndex(of: "Features"))
        XCTAssertLessThan(modelsIdx, featuresIdx)
    }

    func testTCADetectsAppFeatureAsAppLayer() throws {
        let root = try makeProject([
            "AppFeature":     ["App":     ["CounterFeature"]],
            "CounterFeature": ["Counter": ["Foundation"]],
            "Models":         ["User":    ["Foundation"]],
        ])
        let yaml = try ConfigGenerator(root: root, packagesDir: nil).generate(mode: .tca)
        let config = try YAMLDecoderShim.decode(yaml)

        let app = try XCTUnwrap(config.layers.first { $0.name == "App" })
        XCTAssertTrue(app.modules.contains("AppFeature"))

        // AppFeature must NOT appear in the Features layer.
        let features = config.layers.first { $0.name == "Features" }
        XCTAssertFalse(features?.modules.contains("AppFeature") ?? false)
    }

    func testTCADetectsClientModulesAsDependencies() throws {
        let root = try makeProject([
            "APIClient":      ["Client": ["Foundation"]],
            "CounterFeature": ["Counter": ["Foundation", "APIClient"]],
        ])
        let yaml = try ConfigGenerator(root: root, packagesDir: nil).generate(mode: .tca)
        let config = try YAMLDecoderShim.decode(yaml)

        let deps = try XCTUnwrap(config.layers.first { $0.name == "Dependencies" })
        XCTAssertTrue(deps.isolatePeers)
        XCTAssertTrue(deps.modules.contains("APIClient"))
    }

    // MARK: Security preset

    func testSecurityPresetIsValidAndStandalone() throws {
        let yaml = ConfigGenerator.securityPreset()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sec-preset-\(UUID().uuidString).yml")
        try yaml.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        let config = try Configuration.load(from: url.path)
        XCTAssertNoThrow(try config.validate())
        XCTAssertEqual(config.security?.enabled, true)
        XCTAssertTrue(config.layers.isEmpty)
    }

    func testSecuritySectionAppendsToGeneratedConfig() throws {
        // `init --tca --security` / `init --security` on a project with modules:
        // the security section is appended to whatever mode generated.
        let yaml = "layers:\n  - name: A\n    paths: [Sources/A/**]\n" + ConfigGenerator.securitySection()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sec-append-\(UUID().uuidString).yml")
        try yaml.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        let config = try Configuration.load(from: url.path)
        XCTAssertNoThrow(try config.validate())
        XCTAssertEqual(config.security?.enabled, true)
        XCTAssertFalse(config.layers.isEmpty)
    }
}

/// Tiny helper to decode a YAML string into Configuration in tests.
enum YAMLDecoderShim {
    static func decode(_ yaml: String) throws -> Configuration {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("shim-\(UUID().uuidString).yml")
        try yaml.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        return try Configuration.load(from: url.path)
    }
}
