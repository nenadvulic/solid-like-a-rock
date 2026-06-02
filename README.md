# SolidLikeARock

A tiny, dependency-light Swift CLI that enforces **architectural import rules** in
your codebase using [SwiftSyntax](https://github.com/swiftlang/swift-syntax).

It parses each `.swift` file into a real syntax tree (no fragile regex / `grep`),
finds every `import` statement, figures out which architectural layer the file
belongs to, and fails if a layer imports something it shouldn't. This is a
practical way to enforce the **Dependency Inversion Principle** (the *D* in SOLID)
and Clean Architecture boundaries in CI — dependencies must point inward.

```
Domain  <-  Data  <-  Presentation
        (dependencies point inward)
```

## Install

```bash
git clone https://github.com/nenadvulic/SolidLikeARock.git
cd SolidLikeARock
swift build -c release
cp .build/release/solid-like-a-rock /usr/local/bin/
```

Or run without installing:

```bash
swift run solid-like-a-rock --config .solid.yml Sources
```

## Configure

Create a `.solid.yml` at your project root (see the included example):

```yaml
alwaysAllow:
  - Foundation
  - Combine

layers:
  - name: Domain
    paths: [Sources/Domain]
    allow: [Foundation]          # whitelist: ONLY these may be imported

  - name: Presentation
    paths: [Sources/Presentation]
    deny: [Data]                 # blacklist: never import Data here
```

- **`allow` (whitelist)** — the layer may import *only* these modules. Anything
  else (besides `alwaysAllow` and the layer's own name) is a violation. Use this
  for strict inner layers like `Domain`.
- **`deny` (blacklist)** — these modules are forbidden; everything else is fine.
  Use this for "this layer must not reach across to that one" rules.
- A file is assigned to the **first** layer whose `paths` substring matches it,
  so list more specific paths first.

## Run

```bash
solid-like-a-rock Sources
```

Output uses the `file:line: error: message` format, so violations show up
inline in Xcode and in CI logs:

```
Sources/Domain/User.swift:3: error: SolidLikeARock: layer 'Domain' is not allowed to import 'UIKit'
Sources/Presentation/HomeView.swift:5: error: SolidLikeARock: layer 'Presentation' must not import 'Data'
❌ SolidLikeARock: 2 violation(s) found.
```

Exit code is non-zero when violations are found — drop it straight into a CI step
or an Xcode "Run Script" build phase.

## Why SwiftSyntax instead of regex?

A regex matches `import` inside strings, comments, and `#if` blocks. SwiftSyntax
parses the actual grammar, so `let s = "import Secrets"` is correctly ignored and
conditional imports are handled the same way the compiler sees them.

## License

MIT
