import Foundation

/// Match a file path against a gitignore-style glob pattern.
///
/// - `*`  matches any run of characters within a single path segment (never `/`)
/// - `**` matches any run of characters across segments (including none)
/// - `?`  matches exactly one non-`/` character
/// - everything else is literal
///
/// The pattern is tried at every component boundary of the path, so it does not
/// need to be anchored to the path root: `Sources/Domain/**` matches both
/// `Sources/Domain/User.swift` and `/abs/proj/Sources/Domain/User.swift`, but
/// never `Sources/DomainHelpers/...` (the boundary after `Domain` must align).
public func globMatch(_ path: String, pattern: String) -> Bool {
    let text = Array(path.replacingOccurrences(of: "\\", with: "/"))
    let pat = Array(pattern)

    // Candidate start offsets: the beginning, and every index just after a `/`.
    var starts = [0]
    for (i, ch) in text.enumerated() where ch == "/" { starts.append(i + 1) }

    for start in starts where matchAnchored(pat, 0, text, start) {
        return true
    }
    return false
}

/// Match `pat[pi...]` against `text[ti...]`, requiring the whole remaining text
/// to be consumed.
private func matchAnchored(_ pat: [Character], _ pi0: Int, _ text: [Character], _ ti0: Int) -> Bool {
    var pi = pi0
    var ti = ti0
    while pi < pat.count {
        let c = pat[pi]
        if c == "*" {
            // Collapse a run of `*` and decide single vs double star.
            var j = pi
            while j < pat.count && pat[j] == "*" { j += 1 }
            let isDoubleStar = (j - pi) >= 2
            if j == pat.count {
                // Trailing star(s): `**` matches the rest unconditionally; a
                // single `*` matches the rest only if it has no `/`.
                if isDoubleStar { return true }
                return !text[ti...].contains("/")
            }
            // Try to resume the post-star pattern at every later position.
            var k = ti
            while k <= text.count {
                if matchAnchored(pat, j, text, k) { return true }
                if k < text.count {
                    // A single `*` may not consume a path separator.
                    if !isDoubleStar && text[k] == "/" { break }
                }
                k += 1
            }
            return false
        } else if c == "?" {
            guard ti < text.count, text[ti] != "/" else { return false }
            pi += 1; ti += 1
        } else {
            guard ti < text.count, text[ti] == c else { return false }
            pi += 1; ti += 1
        }
    }
    return ti == text.count
}
