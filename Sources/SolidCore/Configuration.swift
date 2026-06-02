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
    public let paths: [String]
    public let allow: [String]?
    public let deny: [String]?

    public init(name: String, paths: [String], allow: [String]? = nil, deny: [String]? = nil) {
        self.name = name
        self.paths = paths
        self.allow = allow
        self.deny = deny
    }
}

/// Top-level configuration, loaded from a YAML file (default `.solid.yml`).
public struct Configuration: Decodable, Equatable {
    /// Modules every layer is always permitted to import (system frameworks, etc.).
    public let alwaysAllow: [String]
    /// Ordered list of layers. The FIRST layer whose path matches a file wins,
    /// so list more specific paths before broader ones.
    public let layers: [LayerRule]

    public init(alwaysAllow: [String] = [], layers: [LayerRule]) {
        self.alwaysAllow = alwaysAllow
        self.layers = layers
    }

    enum CodingKeys: String, CodingKey {
        case alwaysAllow
        case layers
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.alwaysAllow = (try? c.decode([String].self, forKey: .alwaysAllow)) ?? []
        self.layers = try c.decode([LayerRule].self, forKey: .layers)
    }

    /// Load and decode a configuration from a YAML file on disk.
    public static func load(from path: String) throws -> Configuration {
        let text = try String(contentsOfFile: path, encoding: .utf8)
        return try YAMLDecoder().decode(Configuration.self, from: text)
    }
}
