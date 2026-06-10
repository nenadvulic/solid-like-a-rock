import Foundation

/// Builds a layer-level `GraphModel` from a configuration and a set of files,
/// reusing the same layer resolution and rule checks as `Linter` (no extra scan
/// logic). An edge layer A→B is forbidden if any import on that link violates a
/// rule; intra-layer imports are dropped unless they are peer violations.
public struct GraphBuilder {
    private let config: Configuration

    public init(config: Configuration) { self.config = config }

    public func build(files: [String]) throws -> GraphModel {
        let linter = Linter(config: config)

        // Node order: dependencyOrder first (filtered to declared layers), then
        // any remaining layers in declaration order.
        let layerNames = config.layers.map(\.name)
        let ordered = config.dependencyOrder.filter { layerNames.contains($0) }
        let rest = layerNames.filter { !ordered.contains($0) }
        let nodes = ordered + rest

        // Aggregate by "from\u{0001}to". Forbidden wins over allowed; first
        // violation's reason becomes the label.
        var agg: [String: Agg] = [:]

        for file in files {
            guard let fromLayer = linter.layer(for: file),
                  let source = try? String(contentsOfFile: file, encoding: .utf8) else { continue }
            for imp in ImportCollector.imports(in: source, fileName: file) {
                guard let toLayer = linter.layer(owning: imp.module) else { continue }
                let violation = linter.check(imp, in: fromLayer, file: file)
                if fromLayer.name == toLayer.name, violation == nil { continue }  // drop intra-layer noise
                let key = "\(fromLayer.name)\u{0001}\(toLayer.name)"
                if let v = violation {
                    if agg[key]?.verdict != .forbidden {
                        agg[key] = Agg(verdict: .forbidden, reason: Self.reasonLabel(v.reason))
                    }
                } else if agg[key] == nil {
                    agg[key] = Agg(verdict: .allowed, reason: nil)
                }
            }
        }

        func idx(_ name: String) -> Int { nodes.firstIndex(of: name) ?? nodes.count }
        let edges = agg.map { (key, a) -> GraphModel.Edge in
            let parts = key.split(separator: "\u{0001}", maxSplits: 1).map(String.init)
            return GraphModel.Edge(from: parts[0], to: parts[1], verdict: a.verdict, reason: a.reason)
        }.sorted { (idx($0.from), idx($0.to)) < (idx($1.from), idx($1.to)) }

        return GraphModel(nodes: nodes, edges: edges)
    }

    private struct Agg { var verdict: GraphModel.Verdict; var reason: String? }

    private static func reasonLabel(_ r: Violation.Reason) -> String {
        switch r {
        case .outwardDependency: return "outward"
        case .peerImport:        return "peer"
        case .deniedImport:      return "deny"
        case .notAllowedImport:  return "not allowed"
        case .publicInLeafModule: return "visibility"
        }
    }
}
