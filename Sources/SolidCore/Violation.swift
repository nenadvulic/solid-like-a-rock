import Foundation

/// A single rule violation found in a source file.
public struct Violation: Equatable {
    public enum Reason: Equatable {
        /// The module appears on the layer's `deny` list.
        case deniedImport
        /// The layer uses whitelist mode and the module is not on its `allow` list.
        case notAllowedImport
        /// `dependencyOrder` is set and the layer imports a more-outer layer
        /// (a dependency that points outward instead of inward).
        case outwardDependency
    }

    public let file: String
    public let line: Int
    public let importedModule: String
    public let layer: String
    public let reason: Reason
    /// For `.outwardDependency`, the more-outer layer the imported module belongs to.
    public let targetLayer: String?

    public init(file: String, line: Int, importedModule: String, layer: String,
                reason: Reason, targetLayer: String? = nil) {
        self.file = file
        self.line = line
        self.importedModule = importedModule
        self.layer = layer
        self.reason = reason
        self.targetLayer = targetLayer
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
        }
    }

    /// Xcode / CI-friendly diagnostic line: `path:line: error: message`.
    public var diagnostic: String {
        "\(file):\(line): error: SolidLikeARock: \(message)"
    }
}
