import XCTest
@testable import SolidCore

final class DiscoveryTests: XCTestCase {
    func testFindsConfigByWalkingUp() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("solid-disc-\(UUID().uuidString)")
        let deep = root.appendingPathComponent("a/b/c")
        try fm.createDirectory(at: deep, withIntermediateDirectories: true)
        addTeardownBlock { try? fm.removeItem(at: root) }

        let configURL = root.appendingPathComponent(".solid.yml")
        try "layers: []".write(to: configURL, atomically: true, encoding: .utf8)

        // From a nested directory, discovery walks up to the root config.
        XCTAssertEqual(findConfig(from: deep.path), configURL.path)
    }

    func testReturnsNilWhenNoConfigInAncestry() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("solid-disc-none-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? fm.removeItem(at: root) }
        // A temp dir with no .solid.yml anywhere above it within the tree.
        XCTAssertNil(findConfig(from: root.path, stopAt: root.path))
    }

    func testDefaultExcludesCoverBuildArtefactsAndVCS() {
        XCTAssertTrue(defaultExcludes.contains("/.build/"))
        XCTAssertTrue(defaultExcludes.contains("/Pods/"))
        XCTAssertTrue(defaultExcludes.contains("/.git/"))
    }
}
