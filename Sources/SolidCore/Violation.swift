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

    /// Xcode / CI-friendly diagnostic line: `path:line: error|warning: message`.
    public var diagnostic: String {
        "\(file):\(line): \(severity.rawValue): SolidLikeARock: \(message)"
    }
}
