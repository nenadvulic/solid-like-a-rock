# Contributing

Thanks for your interest in SolidLikeARock! Contributions are welcome.

## Getting started

```bash
git clone https://github.com/nenadvulic/solid-like-a-rock.git
cd solid-like-a-rock
swift build
swift test
```

Requires a Swift 6.0+ toolchain (macOS). The package stays on the Swift 5
language mode (`swiftLanguageModes: [.v5]`); tools-version 6.0 is required only so
the command plugin can invoke the same-package executable.

## How the code is organised

- **`SolidCore`** — all the logic (config model, import collector, linter, config
  generator, reporters). Pure and unit-testable; new behaviour goes here.
- **`SolidCLI`** — a thin CLI layer (`lint` + `init` subcommands).
- **`Plugins/`** — the `solid-lint` command plugin and the `SolidLintBuildTool`
  build-tool plugin.

## Expectations for a PR

- **Test-first.** Add a failing test, then the minimal code to pass it. Logic
  belongs in `SolidCore` with XCTest coverage; integrations that can't be
  unit-tested (plugins) are validated by running against the `CleanArchSample`
  fixture.
- `swift test` is green and the output is clean.
- One focused change per branch; open a PR against `main`.
- Keep all repo wording (code, docs, comments) in English.

## Releases

Tags `vX.Y.Z` on `main` trigger the Release workflow (binary + artifactbundle).
Tag only after a PR is merged, and bump the version references in the README as
part of the release PR.
