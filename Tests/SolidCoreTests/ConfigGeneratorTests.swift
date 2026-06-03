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
