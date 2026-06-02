import XCTest
@testable import SolidCore

/// End-to-end test over the bundled `CleanArchSample` fixture: load the real
/// `.solid.yml`, walk every `.swift` file, and assert we flag exactly the three
/// intentional boundary violations — and nothing else.
final class IntegrationTests: XCTestCase {
    /// Absolute path to `Tests/.../Fixtures/CleanArchSample`, copied into the
    /// test bundle by SwiftPM (`resources: [.copy("Fixtures")]`).
    private func sampleRoot() throws -> String {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "Fixtures/CleanArchSample", withExtension: nil),
            "CleanArchSample fixture missing from the test bundle"
        )
        return url.path
    }

    func testCleanArchSampleHasExactlyThreeViolations() throws {
        let root = try sampleRoot()
        let config = try Configuration.load(from: root + "/.solid.yml")
        let linter = Linter(config: config)

        let files = swiftFiles(under: root + "/Sources")
        XCTAssertEqual(files.count, 8, "expected 8 Swift files in the sample")

        let violations = try linter.lint(files: files)

        // Index by basename so the assertions don't depend on the absolute path.
        let byFile = Dictionary(
            grouping: violations,
            by: { ($0.file as NSString).lastPathComponent }
        )

        XCTAssertEqual(violations.count, 3, "expected exactly 3 violations, got \(violations.count): \(violations.map(\.diagnostic))")

        // Application is whitelist mode → importing the outer Infrastructure layer
        // is "not allowed".
        let badUseCase = try XCTUnwrap(byFile["BadUseCase.swift"]?.first)
        XCTAssertEqual(badUseCase.importedModule, "Infrastructure")
        XCTAssertEqual(badUseCase.layer, "Application")
        XCTAssertEqual(badUseCase.reason, .notAllowedImport)
        XCTAssertEqual(badUseCase.line, 2)

        // Infrastructure deny-lists Presentation.
        let badGateway = try XCTUnwrap(byFile["BadGateway.swift"]?.first)
        XCTAssertEqual(badGateway.importedModule, "Presentation")
        XCTAssertEqual(badGateway.layer, "Infrastructure")
        XCTAssertEqual(badGateway.reason, .deniedImport)
        XCTAssertEqual(badGateway.line, 2)

        // The key DIP boundary: Presentation deny-lists Infrastructure.
        let leakyView = try XCTUnwrap(byFile["LeakyView.swift"]?.first)
        XCTAssertEqual(leakyView.importedModule, "Infrastructure")
        XCTAssertEqual(leakyView.layer, "Presentation")
        XCTAssertEqual(leakyView.reason, .deniedImport)
        XCTAssertEqual(leakyView.line, 2)
    }

    func testCleanFilesProduceNoViolations() throws {
        let root = try sampleRoot()
        let config = try Configuration.load(from: root + "/.solid.yml")
        let linter = Linter(config: config)

        // The well-behaved files must stay silent, including SwiftUI in the
        // deny-mode Presentation layer and the inward Domain/Application imports.
        let cleanFiles = [
            "/Sources/Domain/User.swift",
            "/Sources/Domain/UserRepository.swift",
            "/Sources/Application/FetchUserUseCase.swift",
            "/Sources/Infrastructure/CoreDataUserStore.swift",
            "/Sources/Presentation/UserView.swift",
        ].map { root + $0 }

        let violations = try linter.lint(files: cleanFiles)
        XCTAssertTrue(violations.isEmpty, "clean files should not trip any rule: \(violations.map(\.diagnostic))")
    }
}
