import Foundation

/// Renders a `GraphModel` as a Mermaid `graph TD`. Forbidden edges get a `❌`
/// label and are colored red via a trailing `linkStyle` line (link indices are
/// 0-based over the emitted edge lines, in order).
public struct MermaidRenderer {
    public init() {}

    public func render(_ model: GraphModel) -> String {
        var lines = ["graph TD"]
        var forbidden: [Int] = []
        for (i, e) in model.edges.enumerated() {
            if e.verdict == .forbidden {
                lines.append("  \(e.from) -->|❌ \(e.reason ?? "")| \(e.to)")
                forbidden.append(i)
            } else {
                lines.append("  \(e.from) --> \(e.to)")
            }
        }
        if !forbidden.isEmpty {
            lines.append("  linkStyle \(forbidden.map(String.init).joined(separator: ",")) stroke:#e00,stroke-width:2px")
        }
        return lines.joined(separator: "\n") + "\n"
    }
}

/// Renders a `GraphModel` as Graphviz DOT. Forbidden edges are dashed red.
public struct DotRenderer {
    public init() {}

    public func render(_ model: GraphModel) -> String {
        var lines = ["digraph architecture {", "  rankdir=TB;"]
        for e in model.edges {
            if e.verdict == .forbidden {
                lines.append("  \"\(e.from)\" -> \"\(e.to)\" [color=red, style=dashed, label=\"\(e.reason ?? "")\"];")
            } else {
                lines.append("  \"\(e.from)\" -> \"\(e.to)\";")
            }
        }
        lines.append("}")
        return lines.joined(separator: "\n") + "\n"
    }
}
