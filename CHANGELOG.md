# Changelog

All notable changes to SolidLikeARock. Versions follow the `swift-syntax`-friendly
`0.x` scheme; the project targets a Swift 6.0+ toolchain (macOS).

## [0.4.1]
- **SwiftPM build-tool plugin** (`SolidLintBuildTool`): lints automatically as a
  prebuild step on every `swift build` / Xcode build — violations inline, no
  run-script. Uses a prebuilt binary from the release artifactbundle
  (`binaryTarget(url:checksum:)`).

## [0.4.0]
- **`init` subcommand**: generate a starter `.solid.yml` from the project's real
  inter-module import graph (`--freeze` / heuristic layered mode). Deterministic,
  no LLM. Auto-detects `Packages/<M>/Sources` or `Sources/<M>`.
- **`--reporter text|json|github`** (`--format`/`-f` alias): the `github` reporter
  emits `::error`/`::warning` workflow commands for inline PR annotations.
- **Config auto-discovery**: `.solid.yml` found by walking up the directory tree.
- **Default excludes** (`.build`, `.git`, `Pods`, `DerivedData`, `.swiftpm`).
- Artifactbundle tooling (`scripts/make-artifactbundle.sh` + release workflow).
- Fix: layer path matching handles a trailing slash (`Sources/Domain/`).

## [0.3.0]
- **Baseline** (`--write-baseline` / `--baseline`): fail only on *new* violations.
- **Inline suppressions** `// solid:ignore <reason>` (reason mandatory).
- **Per-layer severity** (`severity: warning|error`, default `error`).

## [0.2.0]
- **`--format json`** machine-readable output + Danger Swift integration example.

## [0.1.5]
- Glob path matching; layer/module decoupling (`modules:`); `dependencyOrder`
  derivation of the inward-dependency rule; `swift package solid-lint` command plugin.

## [0.1.0]
- Initial release: SwiftSyntax-based import linter with per-layer `allow`/`deny`
  rules, `exclude`, and Xcode/CI-friendly diagnostics.
