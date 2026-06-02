import Foundation
import Yams

/// A single architectural layer and the import rules that apply to it.
///
/// A layer is matched to source files by checking whether a file's path
/// contains any of the `paths` substrings. Rules can be expressed two ways:
///
/// - `allow` (whitelist): if present, the layer may ONLY import these modules.
///   Anything else (except `alwaysAllow` modules and the layer's own name) is
///   a violation. This is the strict mode — best for inner layers like Domain.
/// - `deny` (blacklist): these modules may never be imported by this layer.
///   Everything else is fine. Best for "this layer must not reach across to
///   that one" rules, e.g. Presentation must not import Data.
///
/// `allow` and `deny` can be combined; `deny` is checked first.
public struct LayerRule: Decodable, Equatable {
    public let name: String
    /// The modules that belong to this layer. When omitted in YAML it defaults
    /// to `[name]`, so the layer name doubles as its single module (the v0.1.0
    /// behaviour). Listing several modules lets one layer span them, e.g.
    /// `Domain` owning `DomainModels` and `DomainServices`.
    public let modules: [String]
    public let paths: [String]
    public let allow: [String]?
    public let deny: [String]?

    public init(name: String, paths: [String], modules: [String]? = nil,
                allow: [String]? = nil, deny: [String]? = nil) {
        self.name = name
        self.modules = modules ?? [name]
        self.paths = paths
        self.allow = allow
        self.deny = deny
    }

    enum CodingKeys: String, CodingKey {
        case name, modules, paths, allow, deny
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let name = try c.decode(String.self, forKey: .name)
        self.name = name
        self.modules = (try? c.decode([String].self, forKey: .modules)) ?? [name]
        self.paths = try c.decode([String].self, forKey: .paths)
        self.allow = try? c.decode([String].self, forKey: .allow)
        self.deny = try? c.decode([String].self, forKey: .deny)
    }
}

/// Top-level configuration, loaded from a YAML file (default `.solid.yml`).
public struct Configuration: Decodable, Equatable {
    /// Modules every layer is always permitted to import (system frameworks, etc.).
    public let alwaysAllow: [String]
    /// Ordered list of layers. The FIRST layer whose path matches a file wins,
    /// so list more specific paths before broader ones.
    public let layers: [LayerRule]
    /// Layer names from the most INNER (index 0) to the most OUTER. When set,
    /// the linter derives the "dependencies point inward" rule: a layer may
    /// import its own and any more-inner layer, but importing a more-outer layer
    /// is a violation. Empty = disabled (pure v0.1.0 allow/deny behaviour).
    public let dependencyOrder: [String]
    /// Path fragments that exclude a file from scanning entirely. Any file whose
    /// path contains one of these substrings is skipped before layer matching —
    /// use it to keep dependencies and build artefacts (`.build`, `Pods`,
    /// `checkouts`, …) out of the analysis.
    public let exclude: [String]

    public init(alwaysAllow: [String] = [], layers: [LayerRule], exclude: [String] = [],
                dependencyOrder: [String] = []) {
        self.alwaysAllow = alwaysAllow
        self.layers = layers
        self.exclude = exclude
        self.dependencyOrder = dependencyOrder
    }

    enum CodingKeys: String, CodingKey {
        case alwaysAllow
        case layers
        case exclude
        case dependencyOrder
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.alwaysAllow = (try? c.decode([String].self, forKey: .alwaysAllow)) ?? []
        self.layers = try c.decode([LayerRule].self, forKey: .layers)
        self.exclude = (try? c.decode([String].self, forKey: .exclude)) ?? []
        self.dependencyOrder = (try? c.decode([String].self, forKey: .dependencyOrder)) ?? []
    }

    /// Load and decode a configuration from a YAML file on disk.
    public static func load(from path: String) throws -> Configuration {
        let text = try String(contentsOfFile: path, encoding: .utf8)
        return try YAMLDecoder().decode(Configuration.self, from: text)
    }
}
