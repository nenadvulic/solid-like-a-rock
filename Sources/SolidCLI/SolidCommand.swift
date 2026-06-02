import ArgumentParser
import Foundation
import SolidCore

@main
struct SolidCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "solid-like-a-rock",
        abstract: "Enforce architectural import rules in Swift code (SOLID / Clean Architecture boundaries)."
    )

    @Option(name: .shortAndLong, help: "Path to the YAML config file.")
    var config: String = ".solid.yml"

    @Option(name: .shortAndLong, parsing: .upToNextOption,
            help: "Path fragments to skip (e.g. .build Pods checkouts). Added to the config's `exclude`.")
    var exclude: [String] = []

    enum OutputFormat: String, ExpressibleByArgument {
        case text, json
    }

    @Option(name: .shortAndLong, help: "Output format: text (default) or json (for tooling like Danger).")
    var format: OutputFormat = .text

    @Option(name: .customLong("baseline"),
            help: "Path to a baseline file; violations recorded there are ignored (only new ones fail).")
    var baseline: String?

    @Option(name: .customLong("write-baseline"),
            help: "Record all current violations to this file and exit, to baseline an existing codebase.")
    var writeBaseline: String?

    @Argument(help: "Directories or .swift files to scan. Defaults to the current directory.")
    var paths: [String] = ["."]

    func run() throws {
        let configuration: Configuration
        do {
            configuration = try Configuration.load(from: config)
        } catch {
            FileHandle.standardError.write(Data("SolidLikeARock: failed to load config '\(config)': \(error)\n".utf8))
            throw ExitCode.failure
        }

        do {
            try configuration.validate()
        } catch {
            FileHandle.standardError.write(Data("SolidLikeARock: invalid config '\(config)': \(error)\n".utf8))
            throw ExitCode.failure
        }

        let linter = Linter(config: configuration)
        let excludes = configuration.exclude + exclude

        var files: [String] = []
        for path in paths {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
                files += swiftFiles(under: path, excluding: excludes)
            } else if path.hasSuffix(".swift"), !excludes.contains(where: { path.contains($0) }) {
                files.append(path)
            }
        }

        let allViolations = try linter.lint(files: files)
            .sorted(by: { ($0.file, $0.line) < ($1.file, $1.line) })

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

        // JSON mode: emit a pure, parseable array on stdout (no banner lines).
        if format == .json {
            print(try renderJSON(violations))
            if !errors.isEmpty { throw ExitCode.failure }
            return
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
