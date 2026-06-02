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
git clone https://github.com/<you>/SolidLikeARock.git
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
# Skip dependencies and build artefacts (substring match on the full path).
exclude:
  - /.build/
  - /Pods/
  - checkouts

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
- **`exclude`** drops any file whose path contains one of these fragments before
  layer matching — essential for monorepos that vendor dependencies (`.build`,
  `Pods`, SwiftPM `checkouts`). You can also pass them on the CLI:
  `solid-like-a-rock --exclude .build Pods -- Sources`.

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

## Example project

A runnable 4-layer Clean Architecture sample lives at
`Tests/SolidCoreTests/Fixtures/CleanArchSample` and doubles as the integration
test for this tool. It contains five well-behaved files and three files that
intentionally cross a boundary:

```
CleanArchSample/
├─ .solid.yml
└─ Sources/
   ├─ Domain/          User.swift, UserRepository.swift          # pure, imports only Foundation
   ├─ Application/      FetchUserUseCase.swift                    # ✅ imports Domain
   │                    BadUseCase.swift                          # ❌ imports Infrastructure
   ├─ Infrastructure/   CoreDataUserStore.swift                   # ✅ imports Domain (inward)
   │                    BadGateway.swift                          # ❌ imports Presentation
   └─ Presentation/     UserView.swift                            # ✅ SwiftUI + Application
                        LeakyView.swift                           # ❌ imports Infrastructure
```

Run it:

```bash
cd Tests/SolidCoreTests/Fixtures/CleanArchSample
solid-like-a-rock --config .solid.yml Sources
```

Expected output — exactly three violations, exit code 1:

```
Sources/Application/BadUseCase.swift:2: error: SolidLikeARock: layer 'Application' is not allowed to import 'Infrastructure'
Sources/Infrastructure/BadGateway.swift:2: error: SolidLikeARock: layer 'Infrastructure' must not import 'Presentation'
Sources/Presentation/LeakyView.swift:2: error: SolidLikeARock: layer 'Presentation' must not import 'Infrastructure'
❌ SolidLikeARock: 3 violation(s) found.
```

`BadUseCase` trips the whitelist (`Application` may import only `Domain`), while
`BadGateway` and `LeakyView` trip deny-lists — the latter being the key
Dependency Inversion boundary: the UI must never reach into `Infrastructure`.

## Why SwiftSyntax instead of regex?

A regex matches `import` inside strings, comments, and `#if` blocks. SwiftSyntax
parses the actual grammar, so `let s = "import Secrets"` is correctly ignored and
conditional imports are handled the same way the compiler sees them.

## License

MIT
