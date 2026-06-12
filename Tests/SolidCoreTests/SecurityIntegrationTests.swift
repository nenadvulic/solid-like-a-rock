import XCTest
@testable import SolidCore

/// Library-level integration tests pinning the contract `Lint.run()` relies on:
/// one run combines `Linter` (architecture) and `SecurityChecker` findings, and
/// a security-only config is valid without any layers.
final class SecurityIntegrationTests: XCTestCase {
    /// A mini-project: one architecture violation + one security violation.
    private func makeProject() throws -> String {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("sec-int-\(UUID().uuidString)")
        let domain = root.appendingPathComponent("Sources/Domain")
        try FileManager.default.createDirectory(at: domain, withIntermediateDirectories: true)
        try """
        import Presentation
        let apiKey = "sk-live-abcdef123456"
        """.write(to: domain.appendingPathComponent("Bad.swift"), atomically: true, encoding: .utf8)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root.path
    }

    func testArchitectureAndSecurityViolationsInOneRun() throws {
        let root = try makeProject()
        // Layer paths are absolute, matching the convention in IntegrationTests:
        // `Linter.layer(for:)` glob-matches the file's full (temp) path.
        let config = Configuration(
            layers: [LayerRule(name: "Domain", paths: [root + "/Sources/Domain"],
                               deny: ["Presentation"])],
            security: SecurityRules(enabled: true))
        try config.validate()
        let files = swiftFiles(under: root, excluding: defaultExcludes)
        var violations = try Linter(config: config).lint(files: files)
        violations += SecurityChecker(config: config.security!)
            .check(swiftFiles: files, roots: [root], excluding: defaultExcludes)
        XCTAssertEqual(violations.count, 2, "got: \(violations.map(\.diagnostic))")
        XCTAssertTrue(violations.contains { $0.reason == .deniedImport })
        XCTAssertTrue(violations.contains { $0.reason == .securityIssue && $0.importedModule == "hardcodedSecret" })
    }

    func testSecurityOnlyConfigNeedsNoLayers() throws {
        let root = try makeProject()
        let config = Configuration(security: SecurityRules(enabled: true))
        XCTAssertNoThrow(try config.validate())
        let files = swiftFiles(under: root, excluding: defaultExcludes)
        XCTAssertTrue(try Linter(config: config).lint(files: files).isEmpty)  // no layers → no import findings
        let violations = SecurityChecker(config: config.security!)
            .check(swiftFiles: files, roots: [root], excluding: defaultExcludes)
        XCTAssertEqual(violations.map(\.importedModule), ["hardcodedSecret"])
    }
}
