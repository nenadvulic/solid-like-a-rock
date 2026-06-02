import Foundation
import PackagePlugin

/// `swift package solid-lint [args...]`
///
/// Thin wrapper that locates the `solid-like-a-rock` executable from the build
/// graph and forwards all arguments to it. With no arguments it lints the
/// package's `Sources` directory using a `.solid.yml` at the package root, so
/// the common case is just `swift package solid-lint`.
@main
struct SolidLint: CommandPlugin {
    func performCommand(context: PluginContext, arguments: [String]) async throws {
        let tool = try context.tool(named: "solid-like-a-rock")

        // Default to a conventional layout when invoked with no extra arguments.
        let forwarded: [String]
        if arguments.isEmpty {
            let root = context.package.directory
            forwarded = ["--config", root.appending("/.solid.yml").string,
                         root.appending("/Sources").string]
        } else {
            forwarded = arguments
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool.path.string)
        process.arguments = forwarded
        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            // Surface the tool's non-zero exit (violations found) as a plugin failure.
            throw SolidLintError.violationsFound(Int(process.terminationStatus))
        }
    }
}

enum SolidLintError: Error, CustomStringConvertible {
    case violationsFound(Int)

    var description: String {
        switch self {
        case .violationsFound(let code):
            return "solid-like-a-rock reported violations (exit code \(code))."
        }
    }
}
