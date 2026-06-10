import ArgumentParser
import Foundation
import SolidCore

struct Graph: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "graph",
        abstract: "Emit a layer-level architecture diagram (Mermaid or DOT) from the real import graph."
    )

    enum Format: String, ExpressibleByArgument { case mermaid, dot }

    @Option(name: .shortAndLong, help: "Path to the YAML config. If omitted, .solid.yml is discovered by walking up.")
    var config: String?

    @Option(name: .shortAndLong, parsing: .upToNextOption,
            help: "Path fragments to skip. Added to the config's `exclude`.")
    var exclude: [String] = []

    @Option(name: [.customLong("format"), .short],
            help: "Output format: mermaid (default) or dot.")
    var format: Format = .mermaid

    @Argument(help: "Directories or .swift files to scan. Defaults to the current directory.")
    var paths: [String] = ["."]

    func run() throws {
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

        guard !configuration.layers.isEmpty else {
            FileHandle.standardError.write(Data("SolidLikeARock: graph needs a .solid.yml with `layers`; run `init` to generate one.\n".utf8))
            throw ExitCode.failure
        }

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

        let model = try GraphBuilder(config: configuration).build(files: files)
        let output = format == .mermaid ? MermaidRenderer().render(model) : DotRenderer().render(model)
        print(output, terminator: "")
    }
}
