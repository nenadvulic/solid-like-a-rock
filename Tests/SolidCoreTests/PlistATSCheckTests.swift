import XCTest
@testable import SolidCore

final class PlistATSCheckTests: XCTestCase {
    private func writePlist(_ dict: [String: Any], name: String = "Info.plist",
                            subdir: String = "App") throws -> (root: String, file: String) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("plist-ats-\(UUID().uuidString)")
        let dir = root.appendingPathComponent(subdir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent(name)
        let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
        try data.write(to: file)
        return (root.path, file.path)
    }

    func testArbitraryLoadsTrueIsFlagged() throws {
        let (root, file) = try writePlist(
            ["NSAppTransportSecurity": ["NSAllowsArbitraryLoads": true]])
        let violations = PlistATSCheck(severity: .error).check(roots: [root], excluding: [])
        XCTAssertEqual(violations.count, 1)
        XCTAssertEqual(violations[0].file, file)
        XCTAssertEqual(violations[0].line, 1)
        XCTAssertEqual(violations[0].importedModule, "cleartextHTTP")
        XCTAssertEqual(violations[0].layer, "Network")
        XCTAssertEqual(violations[0].reason, .securityIssue)
    }

    func testArbitraryLoadsFalseAndAbsentAreNotFlagged() throws {
        let (root1, _) = try writePlist(
            ["NSAppTransportSecurity": ["NSAllowsArbitraryLoads": false]])
        XCTAssertTrue(PlistATSCheck(severity: .error).check(roots: [root1], excluding: []).isEmpty)
        let (root2, _) = try writePlist(["CFBundleName": "App"])
        XCTAssertTrue(PlistATSCheck(severity: .error).check(roots: [root2], excluding: []).isEmpty)
    }

    func testNonInfoPlistsAndExcludedPathsAreSkipped() throws {
        let (root1, _) = try writePlist(
            ["NSAppTransportSecurity": ["NSAllowsArbitraryLoads": true]], name: "Other.plist")
        XCTAssertTrue(PlistATSCheck(severity: .error).check(roots: [root1], excluding: []).isEmpty)
        let (root2, _) = try writePlist(
            ["NSAppTransportSecurity": ["NSAllowsArbitraryLoads": true]], subdir: "Pods/Lib")
        XCTAssertTrue(PlistATSCheck(severity: .error)
            .check(roots: [root2], excluding: ["/Pods/"]).isEmpty)
    }

    func testCorruptPlistIsSkippedSilently() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("plist-ats-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "not a plist".write(to: root.appendingPathComponent("Info.plist"),
                                atomically: true, encoding: .utf8)
        XCTAssertTrue(PlistATSCheck(severity: .error).check(roots: [root.path], excluding: []).isEmpty)
    }
}
