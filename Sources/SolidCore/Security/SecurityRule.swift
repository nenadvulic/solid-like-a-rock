import SwiftSyntax

/// One raw finding produced by a rule, before severity resolution and
/// solid:ignore filtering (both are the engine's job).
public struct SecurityFinding: Equatable {
    public let line: Int
    public let message: String
    /// The node that fired, used by the engine for solid:ignore lookup.
    public let node: Syntax?

    public init(line: Int, message: String, node: Syntax? = nil) {
        self.line = line
        self.message = message
        self.node = node
    }

    public static func == (a: SecurityFinding, b: SecurityFinding) -> Bool {
        (a.line, a.message) == (b.line, b.message)
    }
}

/// A single security detection. One struct per rule; the engine parses each
/// file once and hands every active rule the same tree.
public protocol SecurityRule {
    static var id: String { get }
    /// Keychain, Crypto, Network, Auth or Logging.
    static var category: String { get }
    static var defaultSeverity: Severity { get }
    init()
    func check(_ tree: SourceFileSyntax, file: String,
               converter: SourceLocationConverter) -> [SecurityFinding]
}

/// Identifier-name fragments that indicate a secret (used by several rules).
/// Whole-word, case-insensitive matching via `matchesSensitiveName`.
let secretNameWords = ["apikey", "key", "secret", "token", "password", "credential", "passphrase"]

/// Identifier-name fragments that indicate PII (used by several rules).
let piiNameWords = ["email", "phone", "address", "name", "username", "userid", "user",
                    "token", "password", "ssn", "dob", "birthdate"]

/// Whole-word match: `apiKey`, `api_key`, `API_KEY` all match "apikey"/"key";
/// `monkey` must NOT match "key". Splits camelCase / snake_case into words.
func matchesSensitiveName(_ identifier: String, words: [String]) -> Bool {
    let lowered = identifier.lowercased()
    if words.contains(lowered) { return true }
    // Split on underscores and lowercase→uppercase camel boundaries.
    var parts: [String] = []
    var current = ""
    for char in identifier {
        if char == "_" || char == "-" {
            if !current.isEmpty { parts.append(current.lowercased()); current = "" }
        } else if char.isUppercase, let last = current.last, last.isLowercase {
            parts.append(current.lowercased()); current = String(char)
        } else {
            current.append(char)
        }
    }
    if !current.isEmpty { parts.append(current.lowercased()) }
    // Also try adjacent-pair joins so `api_key` matches "apikey".
    var candidates = Set(parts)
    for i in parts.indices.dropLast() { candidates.insert(parts[i] + parts[i + 1]) }
    return words.contains { candidates.contains($0) }
}
