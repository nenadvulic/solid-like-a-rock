import Foundation

/// Render violations as a machine-readable JSON array — one object per
/// violation with stable keys. Intended for tooling (Danger, dashboards, …)
/// that needs to consume results without parsing the human diagnostic text.
///
/// Each element: `{ file, line, module, layer, reason, targetLayer?, message }`.
public func renderJSON(_ violations: [Violation]) throws -> String {
    let objects = violations.map { v -> [String: Any] in
        var dict: [String: Any] = [
            "file": v.file,
            "line": v.line,
            "module": v.importedModule,
            "layer": v.layer,
            "reason": v.reason.rawValue,
            "message": v.message,
        ]
        if let target = v.targetLayer { dict["targetLayer"] = target }
        return dict
    }
    let data = try JSONSerialization.data(
        withJSONObject: objects,
        options: [.prettyPrinted, .sortedKeys]
    )
    return String(decoding: data, as: UTF8.self)
}
