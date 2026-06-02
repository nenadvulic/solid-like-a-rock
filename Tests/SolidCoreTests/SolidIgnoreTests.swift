import XCTest
@testable import SolidCore

final class SolidIgnoreTests: XCTestCase {
    func testTrailingIgnoreWithReasonIsCaptured() {
        let imports = ImportCollector.imports(in: "import UIKit // solid:ignore needed for legacy bridge\n")
        XCTAssertEqual(imports.first?.module, "UIKit")
        XCTAssertEqual(imports.first?.ignoreReason, "needed for legacy bridge")
    }

    func testLeadingIgnoreOnLineAboveIsCaptured() {
        let source = """
        // solid:ignore temporary during migration
        import UIKit
        """
        XCTAssertEqual(ImportCollector.imports(in: source).first?.ignoreReason,
                       "temporary during migration")
    }

    func testIgnoreWithoutReasonIsNotASuppression() {
        // Reason is mandatory: a bare directive must not suppress.
        let imports = ImportCollector.imports(in: "import UIKit // solid:ignore\n")
        XCTAssertNil(imports.first?.ignoreReason)
    }

    func testPlainImportHasNoIgnoreReason() {
        XCTAssertNil(ImportCollector.imports(in: "import UIKit\n").first?.ignoreReason)
    }

    func testLinterSkipsSuppressedImport() {
        let layer = LayerRule(name: "Domain", paths: ["Sources/Domain/**"], deny: ["UIKit"])
        let linter = Linter(config: Configuration(layers: [layer]))
        let suppressed = ImportRef(module: "UIKit", fullPath: "UIKit", line: 1,
                                   ignoreReason: "approved exception")
        XCTAssertNil(linter.check(suppressed, in: layer, file: "Sources/Domain/X.swift"))
    }
}
