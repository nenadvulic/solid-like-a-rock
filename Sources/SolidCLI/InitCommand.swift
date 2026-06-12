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

    @Flag(help: "Generate a TCA (The Composable Architecture 1.x) preset config with isolatePeers rules.")
    var tca = false

    @Flag(help: "Enable the security checks section (composable with --tca/--freeze; alone, generates a security-only config).")
    var security = false

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

        let mode: InitMode
        if tca {
            mode = .tca
        } else if freeze {
            mode = .freeze
        } else {
            mode = .layered
        }

        let generator = ConfigGenerator(root: path, packagesDir: packagesDir)

        let yaml: String
        do {
            let base = try generator.generate(mode: mode)
            yaml = security ? base + ConfigGenerator.securitySection() : base
        } catch ConfigGeneratorError.noModules where security {
            // --security alone on an empty/module-less project: emit a standalone preset.
            yaml = ConfigGenerator.securityPreset()
        } catch {
            FileHandle.standardError.write(Data("SolidLikeARock: init failed: \(error)\n".utf8))
            throw ExitCode.failure
        }

        try yaml.write(toFile: outputPath, atomically: true, encoding: .utf8)

        let layerCount = yaml.components(separatedBy: "\n  - name:").count - 1
        print("✅ SolidLikeARock: wrote \(outputPath)")
        if tca {
            print("   mode: tca, layers: \(layerCount)")
        } else {
            print("   mode: \(freeze ? "freeze" : "layered"), modules: \(layerCount)")
        }
        if security {
            print("   security checks: enabled")
        }
        if yaml.contains("# WARNING: import cycles") {
            print("   ⚠️  import cycles detected — see the comment header in the generated file.")
        }
    }
}
