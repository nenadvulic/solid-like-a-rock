import ArgumentParser
import Foundation
import SolidCore

struct Init: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "init",
        abstract: "Generate a starter .solid.yml by analysing the project's real import graph."
    )

    @Flag(help: "Freeze the current state: deny every local module a module doesn't import today (0 violations now, bites on new cross-module deps).")
    var freeze = false

    @Option(name: .shortAndLong, help: "Output file (default: <path>/.solid.yml).")
    var output: String?

    @Flag(help: "Allow overwriting an existing output file.")
    var force = false

    @Option(name: .customLong("packages-dir"), help: "Directory containing the modules (otherwise auto-detected).")
    var packagesDir: String?

    @Argument(help: "Project root to analyse (default: \".\").")
    var path: String = "."

    func run() throws {
        let outputPath = output ?? (path as NSString).appendingPathComponent(".solid.yml")

        if FileManager.default.fileExists(atPath: outputPath), !force {
            FileHandle.standardError.write(Data("SolidLikeARock: \(outputPath) already exists; pass --force to overwrite.\n".utf8))
            throw ExitCode.failure
        }

        let mode: InitMode = freeze ? .freeze : .layered
        let generator = ConfigGenerator(root: path, packagesDir: packagesDir)

        let yaml: String
        do {
            yaml = try generator.generate(mode: mode)
        } catch {
            FileHandle.standardError.write(Data("SolidLikeARock: init failed: \(error)\n".utf8))
            throw ExitCode.failure
        }

        try yaml.write(toFile: outputPath, atomically: true, encoding: .utf8)

        // stdout summary.
        let layerCount = yaml.components(separatedBy: "\n  - name:").count - 1
        print("✅ SolidLikeARock: wrote \(outputPath)")
        print("   mode: \(freeze ? "freeze" : "layered"), modules: \(layerCount)")
        if yaml.contains("# WARNING: import cycles") {
            print("   ⚠️  import cycles detected — see the comment header in the generated file.")
        }
    }
}
