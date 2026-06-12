import SwiftSyntax

/// One raw finding produced by a rule, before severity resolution and
/// solid:ignore filtering (both are the engine's job).
public struct SecurityFinding: Equatable {
    public let line: Int
    public let message: String
    /// The node that fired, used by the engine for solid:ignore lookup.
    /// Rules should always attach the firing node — findings without a node
    /// cannot be suppressed with solid:ignore.
    public let node: Syntax?

    public init(line: Int, message: String, node: Syntax? = nil) {
        self.line = line
        self.message = message
        self.node = node
    }

    /// `node` is ignored because Syntax equality is identity/position-based;
    /// equality exists for asserting observable output (line + message).
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
let secretNameWords = ["apikey", "key", "secret", "token", "password", "credential", "passphrase",
                       "jwt"]

/// Identifier-name fragments that indicate PII (shared calibration: the
/// UserDefaults PII rule today, the logging PII rules to come inherit it).
/// Bare "name"/"user"/"address" are deliberately absent — they flag UI and
/// infrastructure keys (`displayName`, `userInterfaceStyle`, `serverAddress`)
/// far more often than PII. Only qualified pairs are provably personal; the
/// matcher's adjacent-pair join makes `firstName` match "firstname".
let piiNameWords = ["firstname", "lastname", "fullname", "realname",
                    "emailaddress", "homeaddress", "postaladdress", "phonenumber",
                    "email", "phone", "username", "userid",
                    "token", "password", "ssn", "dob", "birthdate"]

/// Whole-word match: `apiKey`, `api_key`, `API_KEY` all match "apikey"/"key";
/// `monkey` must NOT match "key". Splits camelCase / snake_case into words,
/// handling acronym runs (`userIDToken` → user/id/token), letter↔digit
/// boundaries (`key2` → key/2) and trailing plurals (`sessionTokens`).
func matchesSensitiveName(_ identifier: String, words: [String]) -> Bool {
    let lowered = identifier.lowercased()
    if words.contains(lowered) { return true }
    // Split on underscores, camel boundaries (including acronym runs:
    // split before the LAST uppercase of a run followed by lowercase,
    // so `IDToken` → ID + Token) and letter↔digit boundaries.
    var parts: [String] = []
    var current = ""
    let chars = Array(identifier)
    for i in chars.indices {
        let char = chars[i]
        if char == "_" || char == "-" {
            if !current.isEmpty { parts.append(current.lowercased()); current = "" }
        } else if char.isUppercase, let last = current.last, last.isLowercase {
            parts.append(current.lowercased()); current = String(char)
        } else if char.isUppercase, current.last?.isUppercase == true,
                  i + 1 < chars.count, chars[i + 1].isLowercase {
            parts.append(current.lowercased()); current = String(char)
        } else if let last = current.last,
                  (char.isNumber && last.isLetter) || (char.isLetter && last.isNumber) {
            parts.append(current.lowercased()); current = String(char)
        } else {
            current.append(char)
        }
    }
    if !current.isEmpty { parts.append(current.lowercased()) }
    // Also try adjacent-pair joins so `api_key` matches "apikey".
    var candidates = Set(parts)
    for i in parts.indices.dropLast() { candidates.insert(parts[i] + parts[i + 1]) }
    // Naive singularization: `tokens` matches "token" (whole-word semantics
    // are preserved — "donkeys" → "donkey" is not in the list).
    for candidate in candidates where candidate.hasSuffix("s") {
        candidates.insert(String(candidate.dropLast()))
    }
    return words.contains { candidates.contains($0) }
}
