import Foundation
import SwiftSyntax

/// A long, high-entropy base64/hex literal anywhere in the code is probably
/// an embedded key, whatever the variable is called. Warning by default —
/// test fixtures trip it legitimately.
public struct HighEntropySecretRule: SecurityRule {
    public static let id = "highEntropySecret"
    public static let category = "Crypto"
    public static let defaultSeverity = Severity.warning

    public init() {}

    public func check(_ tree: SourceFileSyntax, file: String,
                      converter: SourceLocationConverter) -> [SecurityFinding] {
        final class V: SyntaxVisitor {
            var findings: [SecurityFinding] = []
            let converter: SourceLocationConverter
            init(converter: SourceLocationConverter) {
                self.converter = converter
                super.init(viewMode: .sourceAccurate)
            }
            override func visit(_ node: StringLiteralExprSyntax) -> SyntaxVisitorContinueKind {
                // Two gates, because the alphabets cap entropy differently:
                // - Base64: threshold 4.5 bits/char calibrated against the 48-char fixture
                //   "dGhpc2lzYXZlcnlsb25nc2VjcmV0a2V5MTIzNDU2Nzg5MA==" (entropy ≈ 4.61,
                //   29 distinct chars over 48), length >= 20.
                // - Hex: a 16-symbol alphabet caps at 4.0 bits/char, so the base64
                //   threshold is unreachable. Hex keys get length >= 32 (a 128-bit key)
                //   and entropy > 3.5 — near-uniform hex digits clear it, English-y
                //   hex-charset words like "deadbeef…" sit around 2 bits/char.
                // Negative fixtures: all-'a' (entropy 0.0), English sentence (excluded
                // by charset gate — contains spaces and period), short strings (length gate).
                guard let value = plainTextValue(of: node) else { return .skipChildren }
                let passes: Bool
                if Self.isHexCharset(value) {
                    passes = value.count >= 32 && Self.shannonEntropy(value) > 3.5
                } else {
                    passes = value.count >= 20 && Self.isBase64OrHexCharset(value)
                        && Self.shannonEntropy(value) > 4.5
                }
                guard passes else { return .skipChildren }
                findings.append(SecurityFinding(
                    line: node.startLocation(converter: converter).line,
                    message: "high-entropy literal looks like an embedded key/secret — load it at runtime instead",
                    node: Syntax(node)))
                return .skipChildren
            }
            static func isBase64OrHexCharset(_ s: String) -> Bool {
                let base64 = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=")
                return s.unicodeScalars.allSatisfy { base64.contains($0) }
            }
            static func isHexCharset(_ s: String) -> Bool {
                let hex = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
                return !s.isEmpty && s.unicodeScalars.allSatisfy { hex.contains($0) }
            }
            /// Shannon entropy in bits per character.
            static func shannonEntropy(_ s: String) -> Double {
                var counts: [Character: Int] = [:]
                for c in s { counts[c, default: 0] += 1 }
                let n = Double(s.count)
                return counts.values.reduce(0.0) { acc, c in
                    let p = Double(c) / n
                    return acc - p * log2(p)
                }
            }
        }
        let v = V(converter: converter)
        v.walk(tree)
        return v.findings
    }
}
