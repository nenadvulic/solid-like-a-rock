import ArgumentParser
import Foundation
import SolidCore

@main
struct SolidLikeARock: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "solid-like-a-rock",
        abstract: "Enforce architectural import rules in Swift code (SOLID / Clean Architecture boundaries).",
        subcommands: [Lint.self, Init.self, Graph.self],
        defaultSubcommand: Lint.self   // backwards compatible: bare invocation lints
    )
}

struct Lint: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "lint",
        abstract: "Check imports against the architecture rules in .solid.yml."
    )

    @Option(name: .shortAndLong, help: "Path to the YAML config file. If omitted, .solid.yml is discovered by walking up from the current directory.")
    var config: String?

    @Option(name: .shortAndLong, parsing: .upToNextOption,
            help: "Path fragments to skip (e.g. .build Pods checkouts). Added to the config's `exclude`.")
    var exclude: [String] = []

    enum Reporter: String, ExpressibleByArgument {
        case text, json, github
    }

    // Accepts both `--reporter` (preferred) and `--format`/`-f` (kept for
    // backwards compatibility with earlier versions).
    @Option(name: [.customLong("reporter"), .customLong("format"), .short],
            help: "Output reporter: text (default), json (tooling/Danger), or github (PR annotations).")
    var format: Reporter = .text

    @Option(name: .customLong("baseline"),
            help: "Path to a baseline file; violations recorded there are ignored (only new ones fail).")
    var baseline: String?

    @Option(name: .customLong("write-baseline"),
            help: "Record all current violations to this file and exit, to baseline an existing codebase.")
    var writeBaseline: String?

    @Argument(help: "Directories or .swift files to scan. Defaults to the current directory.")
    var paths: [String] = ["."]

    func run() throws {
        // Resolve the config: explicit `--config`, else discovered by walking up.
        let cwd = FileManager.default.currentDirectoryPath
        guard let configPath = config ?? findConfig(from: cwd) else {
            FileHandle.standardError.write(Data("SolidLikeARock: no .solid.yml found (searched up from \(cwd)); pass --config.\n".utf8))
            throw ExitCode.failure
        }

        let configuration: Configuration
        do {
            configuration = try Configuration.load(from: configPath)
        } catch {
            FileHandle.standardError.write(Data("SolidLikeARock: failed to load config '\(configPath)': \(error)\n".utf8))
            throw ExitCode.failure
        }

        do {
            try configuration.validate()
        } catch {
            FileHandle.standardError.write(Data("SolidLikeARock: invalid config '\(configPath)': \(error)\n".utf8))
            throw ExitCode.failure
        }

        let linter = Linter(config: configuration)
        let excludes = defaultExcludes + configuration.exclude + exclude

        var files: [String] = []
        for path in paths {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
                files += swiftFiles(under: path, excluding: excludes)
            } else if path.hasSuffix(".swift"), !excludes.contains(where: { path.contains($0) }) {
                files.append(path)
            }
        }

        var allViolations = try linter.lint(files: files)
        if let vis = configuration.visibility, vis.warnPublicInLeafModules {
            allViolations += VisibilityChecker(rules: vis)
                .check(roots: paths, excluding: excludes)
        }
        allViolations.sort(by: { ($0.file, $0.line) < ($1.file, $1.line) })

        // --write-baseline: snapshot the current violations and exit successfully.
        if let path = writeBaseline {
            try Baseline(violations: allViolations).write(to: path)
            print("📝 SolidLikeARock: wrote baseline with \(allViolations.count) violation(s) to \(path).")
            return
        }

        // --baseline: drop violations already recorded, so only new ones remain.
        let violations: [Violation]
        if let path = baseline {
            violations = try Baseline.load(from: path).newViolations(in: allViolations)
        } else {
            violations = allViolations
        }

        // A build only fails on `.error` violations; `.warning` are reported but tolerated.
        let errors = violations.filter { $0.severity == .error }

        // Machine reporters: emit a clean, parseable stream (no banner lines),
        // but keep the exit code reflecting error-level violations.
        switch format {
        case .json:
            print(try renderJSON(violations))
            if !errors.isEmpty { throw ExitCode.failure }
            return
        case .github:
            if !violations.isEmpty { print(renderGitHub(violations)) }
            if !errors.isEmpty { throw ExitCode.failure }
            return
        case .text:
            break
        }

        guard !violations.isEmpty else {
            print("✅ SolidLikeARock: no import violations (\(files.count) file(s) checked).")
            return
        }

        for violation in violations {
            print(violation.diagnostic)
        }

        let warnings = violations.count - errors.count
        if errors.isEmpty {
            print("⚠️  SolidLikeARock: \(warnings) warning(s), 0 error(s).")
            return
        }
        print("❌ SolidLikeARock: \(errors.count) error(s), \(warnings) warning(s).")
        throw ExitCode.failure
    }
}
