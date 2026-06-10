import XCTest
@testable import SolidCore

final class GraphBuilderTests: XCTestCase {
    private func fixtureRoot(_ name: String) throws -> String {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: nil),
            "\(name) fixture missing from the test bundle"
        )
        return url.path
    }

    /// TCAAppSample: Models <- Dependencies <- Features <- App, with one peer
    /// violation (LoginFeature importing CounterFeature inside the Features layer).
    func testTCASampleBuildsLayerGraphWithPeerSelfLoop() throws {
        let root = try fixtureRoot("TCAAppSample")
        let config = try Configuration.load(from: root + "/.solid.yml")
        let model = try GraphBuilder(config: config).build(files: swiftFiles(under: root + "/Sources"))

        XCTAssertEqual(model.nodes, ["Models", "Dependencies", "Features", "App"])
        XCTAssertEqual(model.edges, [
            .init(from: "Dependencies", to: "Models", verdict: .allowed),
            .init(from: "Features", to: "Models", verdict: .allowed),
            .init(from: "Features", to: "Dependencies", verdict: .allowed),
            .init(from: "Features", to: "Features", verdict: .forbidden, reason: "peer"),
            .init(from: "App", to: "Features", verdict: .allowed),
        ], "got: \(model.edges)")
    }

    /// CleanArchSample: the two intentional outward imports become red edges.
    func testCleanArchSampleMarksOutwardEdgesForbidden() throws {
        let root = try fixtureRoot("CleanArchSample")
        let config = try Configuration.load(from: root + "/.solid.yml")
        let model = try GraphBuilder(config: config).build(files: swiftFiles(under: root + "/Sources"))

        let forbidden = model.edges.filter { $0.verdict == .forbidden }
        XCTAssertTrue(forbidden.contains { $0.from == "Application" && $0.to == "Infrastructure" },
                      "expected Application→Infrastructure forbidden; got \(model.edges)")
        XCTAssertTrue(forbidden.contains { $0.from == "Infrastructure" && $0.to == "Presentation" },
                      "expected Infrastructure→Presentation forbidden; got \(model.edges)")
    }
}
