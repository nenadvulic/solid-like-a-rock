// Example Danger Swift integration for SolidLikeARock.
//
// Lints ONLY the Swift files touched by the PR (so contributors aren't blamed
// for pre-existing violations) and posts each one as an inline comment on the
// exact line, using the tool's `--format json` output.
//
// Setup:
//   1. Install Danger Swift (https://danger.systems/swift/) and solid-like-a-rock.
//   2. Drop this file at your repo root as `Dangerfile.swift`.
//   3. Run `danger-swift ci` in your CI job.

import Danger
import Foundation

let danger = Danger()

let changedSwiftFiles = (danger.git.modifiedFiles + danger.git.createdFiles)
    .filter { $0.hasSuffix(".swift") }

if !changedSwiftFiles.isEmpty {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/local/bin/solid-like-a-rock")
    process.arguments = ["--format", "json", "--config", ".solid.yml"] + changedSwiftFiles

    let stdout = Pipe()
    process.standardOutput = stdout
    try? process.run()
    process.waitUntilExit()

    struct Violation: Decodable {
        let file: String
        let line: Int
        let message: String
    }

    let data = stdout.fileHandleForReading.readDataToEndOfFile()
    if let violations = try? JSONDecoder().decode([Violation].self, from: data) {
        for violation in violations {
            // `fail` marks the PR as failing and pins the comment to the line.
            fail(message: "🪨 \(violation.message)", file: violation.file, line: violation.line)
        }
    }
}
