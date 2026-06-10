import XCTest
@testable import SolidCore

final class GraphRendererTests: XCTestCase {
    private let model = GraphModel(
        nodes: ["Models", "Features", "App"],
        edges: [
            .init(from: "App", to: "Features", verdict: .allowed),
            .init(from: "Features", to: "Models", verdict: .allowed),
            .init(from: "Features", to: "Features", verdict: .forbidden, reason: "peer"),
            .init(from: "Models", to: "Features", verdict: .forbidden, reason: "outward"),
        ]
    )

    func testMermaidRendersAllowedAndForbiddenEdges() {
        let out = MermaidRenderer().render(model)
        XCTAssertEqual(out, """
        graph TD
          App --> Features
          Features --> Models
          Features -->|❌ peer| Features
          Models -->|❌ outward| Features
          linkStyle 2,3 stroke:#e00,stroke-width:2px

        """)
    }

    func testDotRendersForbiddenEdgesRed() {
        let out = DotRenderer().render(model)
        XCTAssertEqual(out, """
        digraph architecture {
          rankdir=TB;
          "App" -> "Features";
          "Features" -> "Models";
          "Features" -> "Features" [color=red, style=dashed, label="peer"];
          "Models" -> "Features" [color=red, style=dashed, label="outward"];
        }

        """)
    }
}
