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

        let linter = Linter(config: configuration)

        var files: [String] = []
        for path in paths {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
                files += swiftFiles(under: path)
            } else if path.hasSuffix(".swift") {
                files.append(path)
            }
        }

        let violations = try linter.lint(files: files)

        guard !violations.isEmpty else {
            print("✅ SolidLikeARock: no import violations (\(files.count) file(s) checked).")
            return
        }

        for violation in violations.sorted(by: { ($0.file, $0.line) < ($1.file, $1.line) }) {
            print(violation.diagnostic)
        }
        print("❌ SolidLikeARock: \(violations.count) violation(s) found.")
        throw ExitCode.failure
    }
}
