import Foundation

/// NSAllowsArbitraryLoads=true turns App Transport Security off for every
/// connection. Scans `Info.plist` files (exactly that name) under the lint
/// roots; corrupt/unreadable plists are skipped like unreadable Swift files.
public struct PlistATSCheck {
    public static let id = "cleartextHTTP"
    public static let category = "Network"
    public static let defaultSeverity = Severity.error

    private let severity: Severity

    public init(severity: Severity) {
        self.severity = severity
    }

    public func check(roots: [String], excluding: [String]) -> [Violation] {
        var violations: [Violation] = []
        for root in roots {
            for file in Self.infoPlists(under: root, excluding: excluding) {
                guard let data = FileManager.default.contents(atPath: file),
                      let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
                      let dict = plist as? [String: Any],
                      let ats = dict["NSAppTransportSecurity"] as? [String: Any],
                      ats["NSAllowsArbitraryLoads"] as? Bool == true
                else { continue }
                violations.append(.security(
                    ruleID: Self.id, category: Self.category,
                    message: "NSAllowsArbitraryLoads is true — App Transport Security is disabled for every connection; scope exceptions per-domain instead",
                    file: file, line: 1, severity: severity))
            }
        }
        return violations
    }

    static func infoPlists(under root: String, excluding: [String]) -> [String] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root, isDirectory: &isDirectory) else { return [] }
        // A single-file root (e.g. `lint Foo.swift`) has no plists of its own.
        guard isDirectory.boolValue else { return [] }
        guard let enumerator = FileManager.default.enumerator(atPath: root) else { return [] }
        var result: [String] = []
        for case let relative as String in enumerator
        where (relative as NSString).lastPathComponent == "Info.plist" {
            let full = (root as NSString).appendingPathComponent(relative)
            if excluding.contains(where: { full.contains($0) }) { continue }
            result.append(full)
        }
        return result.sorted()
    }
}
