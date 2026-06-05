import XCTest
import Yams
@testable import SolidCore

final class VisibilityCheckerTests: XCTestCase {
    private let fm = FileManager.default

    /// root/Sources/<module>/<file>.swift — files given as full source text.
    @discardableResult
    private func makeProject(_ modules: [String: [String: String]]) throws -> String {
        let root = fm.temporaryDirectory.appendingPathComponent("solid-vis-\(UUID().uuidString)")
        for (module, files) in modules {
            let dir = root.appendingPathComponent("Sources/\(module)")
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            for (file, source) in files {
                try source.write(to: dir.appendingPathComponent("\(file).swift"),
                                 atomically: true, encoding: .utf8)
            }
        }
        addTeardownBlock { try? self.fm.removeItem(at: root) }
        return root.path
    }

    func testLeafModulesAreModulesNoOneImports() throws {
        let root = try makeProject([
            "A": ["File": "import B\npublic struct AThing {}\n"],
            "B": ["File": "struct BThing {}\n"],
            "C": ["File": "public enum CThing {}\n"],
        ])
        let graph = ModuleGraph.build(root: root)
        XCTAssertEqual(graph.leafModules.map(\.name).sorted(), ["A", "C"])
    }

    func testVisibilitySectionDecodes() throws {
        let yaml = """
        layers:
          - name: App
            paths: [Sources/App]
        visibility:
          warnPublicInLeafModules: true
          excludeModules: [PublicSDK]
          severity: error
        """
        let config = try YAMLDecoder().decode(Configuration.self, from: yaml)
        XCTAssertEqual(config.visibility?.warnPublicInLeafModules, true)
        XCTAssertEqual(config.visibility?.excludeModules, ["PublicSDK"])
        XCTAssertEqual(config.visibility?.severity, .error)
    }

    func testVisibilitySectionDefaults() throws {
        let yaml = """
        layers:
          - name: App
            paths: [Sources/App]
        visibility:
          warnPublicInLeafModules: true
        """
        let config = try YAMLDecoder().decode(Configuration.self, from: yaml)
        XCTAssertEqual(config.visibility?.excludeModules, [])
        XCTAssertEqual(config.visibility?.severity, .warning)
        // Absent section ⇒ nil (existing configs unchanged):
        let plain = try YAMLDecoder().decode(Configuration.self, from: "layers:\n  - name: App\n    paths: [Sources/App]\n")
        XCTAssertNil(plain.visibility)
    }

    func testPublicInLeafModuleMessage() {
        let v = Violation.publicInLeafModule(module: "Utils", symbol: "Helper",
                                             file: "Sources/Utils/Helper.swift", line: 3,
                                             severity: .warning)
        XCTAssertEqual(v.message,
            "module 'Utils' is not imported by any other module, but declares public symbol 'Helper' — make it internal, or exclude the module")
        XCTAssertTrue(v.diagnostic.contains("warning:"))
        // The factory maps symbol→importedModule and module→layer (reporter compat).
        XCTAssertEqual(v.importedModule, "Helper")
        XCTAssertEqual(v.layer, "Utils")
    }

    private func check(_ root: String, rules: VisibilityRules = .init(warnPublicInLeafModules: true)) -> [Violation] {
        VisibilityChecker(rules: rules).check(roots: [root], excluding: ["/.build/"])
    }

    func testPublicSymbolInLeafModuleIsFlagged() throws {
        let root = try makeProject([
            "Utils": ["Helper": "public struct Helper {}\npublic func freebie() {}\n"],
        ])
        let violations = check(root)
        XCTAssertEqual(violations.count, 2)
        XCTAssertEqual(violations.map(\.importedModule).sorted(), ["Helper", "freebie"])
        XCTAssertEqual(violations.first?.layer, "Utils")
        XCTAssertEqual(violations.first?.reason, .publicInLeafModule)
        XCTAssertEqual(violations.first?.severity, .warning)
    }

    func testConsumedModuleIsNotFlagged() throws {
        let root = try makeProject([
            "Utils": ["Helper": "public struct Helper {}\n"],
            "App":   ["Main": "import Utils\nlet h = Helper()\n"],
        ])
        // Utils is imported by App → not a leaf. App is a leaf but has no publics.
        XCTAssertEqual(check(root), [])
    }

    func testExcludedModuleIsNotFlagged() throws {
        let root = try makeProject([
            "PublicSDK": ["API": "public struct API {}\n"],
        ])
        let rules = VisibilityRules(warnPublicInLeafModules: true, excludeModules: ["PublicSDK"])
        XCTAssertEqual(check(root, rules: rules), [])
    }

    func testExecutableModuleIsNotFlagged() throws {
        let root = try makeProject([
            "ToolMain": ["main": "public let entry = 1\n"],                       // main.swift
            "ToolApp":  ["App": "@main\npublic struct App { public static func main() {} }\n"],
        ])
        XCTAssertEqual(check(root), [])
    }

    func testMembersOfPublicTypeAreNotIndividuallyFlagged() throws {
        let root = try makeProject([
            "Utils": ["Box": "public struct Box {\n  public var value = 0\n  public func touch() {}\n}\n"],
        ])
        let violations = check(root)
        XCTAssertEqual(violations.map(\.importedModule), ["Box"])  // the type, not its members
    }

    func testEveryBindingOfAMultiBindingVarIsFlagged() throws {
        let root = try makeProject([
            "Utils": ["Pair": "public let a = 1, b = 2\n"],
        ])
        XCTAssertEqual(check(root).map(\.importedModule).sorted(), ["a", "b"])
    }

    func testSeverityComesFromRules() throws {
        let root = try makeProject([
            "Utils": ["Helper": "open class Helper {}\n"],
        ])
        let rules = VisibilityRules(warnPublicInLeafModules: true, severity: .error)
        XCTAssertEqual(check(root, rules: rules).first?.severity, .error)
    }

    func testBaselinedVisibilityViolationIsNotReportedAgain() throws {
        let root = try makeProject([
            "Utils": ["Helper": "public struct Helper {}\n"],
        ])
        let all = check(root)
        XCTAssertEqual(all.count, 1)
        let baseline = Baseline(violations: all)
        XCTAssertEqual(baseline.newViolations(in: check(root)), [])
    }

    func testScanPathInsideThePackageResolvesToThePackageRoot() throws {
        // The universal CLI usage is `lint Sources` — the checker must walk up
        // from the scan path to the directory that actually contains Sources/<M>.
        let root = try makeProject([
            "Utils": ["Helper": "public struct Helper {}\n"],
        ])
        let viaSources = VisibilityChecker(rules: .init(warnPublicInLeafModules: true))
            .check(roots: [root + "/Sources"], excluding: [])
        XCTAssertEqual(viaSources.map(\.importedModule), ["Helper"])
    }

    func testOverlappingRootsDoNotDuplicateViolations() throws {
        let root = try makeProject([
            "Utils": ["Helper": "public struct Helper {}\n"],
        ])
        // `lint Sources Sources/Utils` (or Sources + a sibling dir) must not
        // run the same package root twice.
        let violations = VisibilityChecker(rules: .init(warnPublicInLeafModules: true))
            .check(roots: [root + "/Sources", root], excluding: [])
        XCTAssertEqual(violations.count, 1)
    }
}
