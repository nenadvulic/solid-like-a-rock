# Changelog

All notable changes to SolidLikeARock. Versions follow the `swift-syntax`-friendly
`0.x` scheme; the project targets a Swift 6.0+ toolchain (macOS).

## [Unreleased]

## [0.8.0]
- **Architecture graph** (`graph` subcommand): emit a layer-level diagram of your
  modules straight from the real import graph — Mermaid (default, renders natively
  in a GitHub README/PR) or DOT (`--format dot`). Rule-violating edges are drawn
  red. A visualization, not a gate (always exits 0); reuses the existing engine,
  no new dependencies.
- **Claude Code integration**: a `PostToolUse` hook
  (`.claude/hooks/solid-lint-changed.sh` + `.claude/settings.json`) runs the linter
  automatically after an agent edits a `.swift` file and feeds any violation back,
  so the boundary gets fixed in the same turn. See `.claude/README.md`.
- Docs: "Architecture graph" README section (bundled TCA sample + an isowords
  88-module real-world example) and a TCA `isolatePeers` demo GIF (`demo/tca.tape`).

## [0.7.0]
- **TCA support**: `isolatePeers: true` layer flag — modules within the same layer
  cannot import each other. Enforces the TCA rule that feature modules are peers
  and must not import siblings; only the root `AppFeature` composer may.
- **`init --tca`**: detects TCA 1.x projects by module naming (`*Feature`,
  `*Client`, `AppFeature`, `Models`) and file content (`@Reducer`,
  `@DependencyClient`), and generates a `dependencyOrder` config with
  `isolatePeers: true` on the Features and Dependencies layers.
- **`examples/tca.solid.yml`**: ready-to-use TCA preset template.

## [0.6.0]
- Build-tool plugin: `SolidLikeARockBinary` binary target now resolves the
  **v0.5.0** artifactbundle (was pinned to v0.4.0 by the two-step release
  chicken-and-egg), so prebuild linting runs the current binary.
- **Linux release binaries** (`linux-x86_64`, `linux-aarch64`), statically
  linked (`--static-swift-stdlib`) — no Swift runtime needed on the host.

## [0.5.0]
- **Visibility rule** (opt-in `visibility:` config section): flag top-level
  `public`/`open` declarations in **leaf modules** (modules no other local
  module imports) — `warnPublicInLeafModules`, `excludeModules`, `severity`
  (default `warning`). Executable modules (`main.swift` / `@main`) are skipped
  automatically; violations are baselineable like any other. Module-level only
  by design — symbol-level unused-public detection is Periphery's job.
- `ModuleGraph`: shared module-discovery + import-graph component (extracted
  from `init`), also used to resolve package roots from scan paths so
  `lint Sources` fires the rule.
- Reproducible benchmark (`scripts/benchmark.sh`, pinned isowords checkout) and
  a README **Performance** section with measured numbers.
- Problem-oriented README rewrite; battle-tested Danger example
  (Homebrew paths, `lint` subcommand, baseline support).

## [0.4.2]
- **Universal macOS binary** (arm64 + x86_64 via `lipo`) — release asset renamed
  to `solid-like-a-rock-macos-universal.tar.gz`; runs under Rosetta without
  `arch -arm64`.
- **Homebrew tap**: `brew tap nenadvulic/solid-like-a-rock && brew install solid-like-a-rock`.
- Docs: Xcode/CocoaPods manual-config guide, "Generate a config with AI" prompt.

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
