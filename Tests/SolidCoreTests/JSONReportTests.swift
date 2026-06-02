import XCTest
@testable import SolidCore

final class JSONReportTests: XCTestCase {
    func testRendersViolationsAsJSONArray() throws {
        let violations = [
            Violation(file: "Sources/UI/View.swift", line: 5, importedModule: "NetworkProvider",
                      layer: "Presentation", reason: .deniedImport),
            Violation(file: "Sources/Domain/Thing.swift", line: 2, importedModule: "PresUI",
                      layer: "Domain", reason: .outwardDependency, targetLayer: "Presentation"),
        ]

        let json = try renderJSON(violations)
        let parsed = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]]
        let array = try XCTUnwrap(parsed)

        XCTAssertEqual(array.count, 2)
        XCTAssertEqual(array[0]["file"] as? String, "Sources/UI/View.swift")
        XCTAssertEqual(array[0]["line"] as? Int, 5)
        XCTAssertEqual(array[0]["module"] as? String, "NetworkProvider")
        XCTAssertEqual(array[0]["layer"] as? String, "Presentation")
        XCTAssertEqual(array[0]["reason"] as? String, "deniedImport")
        XCTAssertNotNil(array[0]["message"] as? String)

        XCTAssertEqual(array[1]["reason"] as? String, "outwardDependency")
        XCTAssertEqual(array[1]["targetLayer"] as? String, "Presentation")
    }

    func testEmptyViolationsRenderEmptyArray() throws {
        let json = try renderJSON([])
        let parsed = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [Any]
        XCTAssertEqual(parsed?.count, 0)
    }
}
