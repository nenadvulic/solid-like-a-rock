import Foundation

/// A record of already-known violations, used to fail the build only on NEW
/// ones — the key to adopting the linter on a living legacy codebase.
///
/// A violation's identity is `file + module + reason` (the line number is
/// deliberately excluded, so edits above an import don't resurface a baselined
/// violation as "new").
public struct Baseline: Equatable {
    private struct Key: Hashable, Codable, Comparable {
        let file: String
        let module: String
        let reason: String

        static func < (a: Key, b: Key) -> Bool {
            (a.file, a.module, a.reason) < (b.file, b.module, b.reason)
        }
    }

    private let keys: Set<Key>

    public init(violations: [Violation]) {
        keys = Set(violations.map(Self.key))
    }

    private init(keys: Set<Key>) {
        self.keys = keys
    }

    private static func key(_ v: Violation) -> Key {
        Key(file: v.file, module: v.importedModule, reason: v.reason.rawValue)
    }

    /// Whether this violation is already recorded in the baseline.
    public func isKnown(_ v: Violation) -> Bool {
        keys.contains(Self.key(v))
    }

    /// The subset of `violations` that are NOT in the baseline.
    public func newViolations(in violations: [Violation]) -> [Violation] {
        violations.filter { !isKnown($0) }
    }

    /// Write the baseline as a stable, diff-friendly JSON array of
    /// `{file, module, reason}` objects (sorted).
    public func write(to path: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(keys.sorted())
        try data.write(to: URL(fileURLWithPath: path))
    }

    /// Load a baseline previously written by `write(to:)`.
    public static func load(from path: String) throws -> Baseline {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let keys = try JSONDecoder().decode([Key].self, from: data)
        return Baseline(keys: Set(keys))
    }
}
