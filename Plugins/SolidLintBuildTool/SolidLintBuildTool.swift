import Foundation
import PackagePlugin

/// Build-tool plugin: runs SolidLikeARock automatically as a *prebuild* step on
/// every `swift build` / Xcode build, so import violations show up inline with
/// no separate run-script. A linter produces no generated sources, so it's a
/// prebuild command (no declared output files needed up front).
///
/// A prebuild command can't build its tool from source, so the executable comes
/// from a prebuilt artifactbundle (`binaryTarget` `SolidLikeARockBinary`).
@main
struct SolidLintBuildTool: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        // Only lint targets that actually have Swift sources.
        guard target is SourceModuleTarget else { return [] }

        let tool = try context.tool(named: "solid-like-a-rock")
        let lintRoot = target.directory.string

        // Prefer a config at the package root; otherwise let the tool discover one
        // by walking up from the linted directory.
        var arguments: [String] = []
        let packageConfig = context.package.directory.appending(".solid.yml").string
        if FileManager.default.fileExists(atPath: packageConfig) {
            arguments += ["--config", packageConfig]
        }
        arguments.append(lintRoot)

        return [
            .prebuildCommand(
                displayName: "SolidLikeARock: lint \(target.name)",
                executable: tool.path,
                arguments: arguments,
                outputFilesDirectory: context.pluginWorkDirectory.appending("Output")
            ),
        ]
    }
}
