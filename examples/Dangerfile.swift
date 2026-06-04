// Example Danger Swift integration for SolidLikeARock.
//
// Lints ONLY the Swift files touched by the PR (so contributors aren't blamed
// for pre-existing violations) and posts each one as an inline comment on the
// exact line, using the tool's `--reporter json` output.
//
// Setup:
//   1. Install Danger Swift (https://danger.systems/swift/) and solid-like-a-rock
//      (`brew tap nenadvulic/solid-like-a-rock && brew install solid-like-a-rock`).
//   2. Drop this file at your repo root as `Dangerfile.swift`.
//   3. Run `danger-swift ci` in your CI job.

import Danger
import Foundation

let danger = Danger()

let changedSwiftFiles = (danger.git.modifiedFiles + danger.git.createdFiles)
    .filter { $0.hasSuffix(".swift") }

// Look the binary up in the usual Homebrew locations (arm64 and x86_64).
let binaryPath = ["/opt/homebrew/bin/solid-like-a-rock", "/usr/local/bin/solid-like-a-rock"]
    .first(where: { FileManager.default.isExecutableFile(atPath: $0) })

if changedSwiftFiles.isEmpty {
    message("No Swift sources changed — skipping architecture lint.")
} else if let binaryPath {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: binaryPath)

    var arguments = ["lint", "--reporter", "json", "--config", ".solid.yml"]
    // Honour the baseline if the repo has one, so only NEW violations surface.
    if FileManager.default.fileExists(atPath: ".solid-baseline.json") {
        arguments += ["--baseline", ".solid-baseline.json"]
    }
    process.arguments = arguments + changedSwiftFiles

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
            // Use `warn(message:file:line:)` instead for report-only feedback.
            fail(message: "🪨 \(violation.message)", file: violation.file, line: violation.line)
        }
    }
} else {
    warn("solid-like-a-rock not installed — skipping architecture lint.")
}
