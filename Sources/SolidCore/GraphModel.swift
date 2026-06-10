import Foundation

/// A layer-level architecture graph: nodes are layer names, edges are aggregated
/// imports between layers, each classified as allowed or a violation.
public struct GraphModel: Equatable {
    public enum Verdict: Equatable { case allowed, forbidden }

    public struct Edge: Equatable {
        public let from: String          // source layer name
        public let to: String            // target layer name (== from for a peer self-loop)
        public let verdict: Verdict
        public let reason: String?       // short label for forbidden edges (e.g. "outward", "peer")

        public init(from: String, to: String, verdict: Verdict, reason: String? = nil) {
            self.from = from
            self.to = to
            self.verdict = verdict
            self.reason = reason
        }
    }

    public let nodes: [String]           // layer names, in display order (outer → inner)
    public let edges: [Edge]             // deduplicated, deterministic order

    public init(nodes: [String], edges: [Edge]) {
        self.nodes = nodes
        self.edges = edges
    }
}
