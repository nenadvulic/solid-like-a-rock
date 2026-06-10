import Foundation

/// A single rule violation found in a source file.
public struct Violation: Equatable {
    public enum Reason: String, Equatable {
        /// The module appears on the layer's `deny` list.
        case deniedImport
        /// The layer uses whitelist mode and the module is not on its `allow` list.
        case notAllowedImport
        /// `dependencyOrder` is set and the layer imports a more-outer layer
        /// (a dependency that points outward instead of inward).
        case outwardDependency
        /// The file's module is a leaf (no other local module imports it) yet
        /// declares a public symbol. `importedModule` carries the SYMBOL name,
        /// `layer` carries the MODULE name.
        case publicInLeafModule
        /// The layer has `isolatePeers: true` and the import is a same-layer peer module.
        case peerImport
    }

    public let file: String
    public let line: Int
    public let importedModule: String
    public let layer: String
    public let reason: Reason
    /// For `.outwardDependency`, the more-outer layer the imported module belongs to.
    public let targetLayer: String?
    /// Whether this violation fails the build (`.error`) or just warns.
    public let severity: Severity

    public init(file: String, line: Int, importedModule: String, layer: String,
                reason: Reason, targetLayer: String? = nil, severity: Severity = .error) {
        self.file = file
        self.line = line
        self.importedModule = importedModule
        self.layer = layer
        self.reason = reason
        self.targetLayer = targetLayer
        self.severity = severity
    }

    /// Build a `.publicInLeafModule` violation. The existing fields are reused
    /// for reporter/baseline compatibility — `importedModule` carries the
    /// SYMBOL name and `layer` the MODULE name — so construction goes through
    /// this factory to keep that mapping in one place.
    public static func publicInLeafModule(module: String, symbol: String,
                                          file: String, line: Int,
                                          severity: Severity) -> Violation {
        Violation(file: file, line: line, importedModule: symbol,
                  layer: module, reason: .publicInLeafModule, severity: severity)
    }

    /// A human-readable explanation of the violation.
    public var message: String {
        switch reason {
        case .deniedImport:
            return "layer '\(layer)' must not import '\(importedModule)'"
        case .notAllowedImport:
            return "layer '\(layer)' is not allowed to import '\(importedModule)'"
        case .outwardDependency:
            let target = targetLayer.map { " (outer layer '\($0)')" } ?? ""
            return "layer '\(layer)' must not depend outward on '\(importedModule)'\(target)"
        case .publicInLeafModule:
            return "module '\(layer)' is not imported by any other module, but declares public symbol '\(importedModule)' — make it internal, or exclude the module"
        case .peerImport:
            return "layer '\(layer)' has isolatePeers enabled — must not import peer module '\(importedModule)'"
        }
    }

    /// Xcode / CI-friendly diagnostic line: `path:line: error|warning: message`.
    public var diagnostic: String {
        "\(file):\(line): \(severity.rawValue): SolidLikeARock: \(message)"
    }
}
