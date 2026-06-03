import Foundation

/// Path fragments excluded from scanning by default — dependencies, build
/// artefacts and VCS metadata that should never be linted. Always applied, in
/// addition to the config's `exclude` and any `--exclude` flags.
public let defaultExcludes: [String] = [
    "/.build/",
    "/.git/",
    "/Pods/",
    "/DerivedData/",
    "/.swiftpm/",
]

/// Locate a config file by walking up the directory tree from `directory`,
/// like git or eslint. Returns the first match, or `nil` if none is found up to
/// the filesystem root (or `stopAt`, exclusive of going above it).
public func findConfig(named name: String = ".solid.yml",
                       from directory: String,
                       stopAt: String? = nil) -> String? {
    let fm = FileManager.default
    var current = URL(fileURLWithPath: directory).standardizedFileURL
    let stop = stopAt.map { URL(fileURLWithPath: $0).standardizedFileURL.path }

    while true {
        let candidate = current.appendingPathComponent(name)
        if fm.fileExists(atPath: candidate.path) {
            return candidate.path
        }
        if current.path == stop { return nil }
        let parent = current.deletingLastPathComponent()
        if parent.path == current.path { return nil }  // reached filesystem root
        current = parent
    }
}
