import Foundation

/// Render violations as GitHub Actions workflow commands, one per line, so they
/// appear as inline annotations on a pull request:
///
///   ::error file=Sources/X.swift,line=5::SolidLikeARock: …
///   ::warning file=A.swift,line=2::SolidLikeARock: …
///
/// `.warning`-severity violations use `::warning`, everything else `::error`.
public func renderGitHub(_ violations: [Violation]) -> String {
    violations.map { v in
        let level = v.severity == .warning ? "warning" : "error"
        return "::\(level) file=\(v.file),line=\(v.line)::SolidLikeARock: \(v.message)"
    }.joined(separator: "\n")
}
