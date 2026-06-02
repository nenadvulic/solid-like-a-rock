import XCTest
@testable import SolidCore

final class ExcludeTests: XCTestCase {
    private func writeTempYAML(_ contents: String) throws -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("solid-exclude-\(UUID().uuidString).yml")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url.path
    }

    func testDecodesExcludeListFromYAML() throws {
        let path = try writeTempYAML("""
        exclude:
          - .build
          - Pods
        layers:
          - name: Domain
            paths: [Sources/Domain]
            allow: [Foundation]
        """)
        let config = try Configuration.load(from: path)
        XCTAssertEqual(config.exclude, [".build", "Pods"])
    }

    func testExcludeDefaultsToEmptyWhenAbsent() throws {
        let path = try writeTempYAML("""
        layers:
          - name: Domain
            paths: [Sources/Domain]
            allow: [Foundation]
        """)
        let config = try Configuration.load(from: path)
        XCTAssertEqual(config.exclude, [])
    }

    func testSwiftFilesSkipsExcludedFragments() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("solid-files-\(UUID().uuidString)")
        addTeardownBlock { try? fm.removeItem(at: root) }

        // root/Sources/App.swift   (kept)
        // root/.build/Dep.swift    (excluded)
        // root/Pods/Lib.swift      (excluded)
        let app = root.appendingPathComponent("Sources/App.swift")
        let dep = root.appendingPathComponent(".build/Dep.swift")
        let pod = root.appendingPathComponent("Pods/Lib.swift")
        for file in [app, dep, pod] {
            try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try "import Foundation\n".write(to: file, atomically: true, encoding: .utf8)
        }

        let found = swiftFiles(under: root.path, excluding: [".build", "Pods"])
            .map { ($0 as NSString).lastPathComponent }
            .sorted()

        XCTAssertEqual(found, ["App.swift"])
    }
}
