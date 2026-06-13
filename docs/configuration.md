# Configuration

How to write and tune `.solid.yml` — bootstrap it with an AI assistant, then
configure layers, the layered `dependencyOrder` mode, the visibility rule, and the
security checks. New here? Start with the [README](../README.md) and
[`init`](../README.md#generate-a-config-init).

## Generate a config with AI

If `init` doesn't cover your project layout — or you want a more tailored starting
point — paste the prompt below into any AI assistant. It works for both SPM and
plain Xcode/CocoaPods projects.

> If you already ran `init`, paste its output alongside the prompt — the AI will
> use it as a starting point and refine the layer groupings.

```
I want to set up solid-like-a-rock (https://github.com/nenadvulic/solid-like-a-rock),
a Swift architecture linter. Please generate a .solid.yml config file for my project.

1. Explore the source directory structure (list folders up to 3 levels deep).
2. Sample `import` statements from Swift files in each main folder to understand
   real dependencies.
3. Identify the architectural layers (Domain, Data, Presentation, Application, etc.)
   from the folder names and import patterns.
4. Generate a .solid.yml with:
   - `exclude` for .build/, Pods/, checkouts/, Tests/
   - `alwaysAllow` for the system frameworks found in the imports
   - One layer per architectural group, with `paths` globs and `deny`/`allow` rules
     that enforce inward-pointing dependencies
   - Use `dependencyOrder` if the project has clearly ordered layers
5. Add a comment with the run command and the --write-baseline command for first use.

My project is at: [PATH]
```

Replace `[PATH]` with your project root. If you already ran `solid-like-a-rock init`,
paste its output at the end of the prompt.

> **Xcode / CocoaPods projects (no SwiftPM modules):** `init` requires a SwiftPM
> module structure to build the import graph. Plain Xcode targets are not
> discoverable, so the command will report *no local modules found*. Write
> `.solid.yml` by hand instead — map your source folders as layers and use
> `deny` lists to enforce the boundaries you care about:
>
> ```yaml
> exclude:
>   - /Pods/
>   - /.build/
>
> alwaysAllow:
>   - Foundation
>   - UIKit
>   - SwiftUI
>   - Combine
>
> layers:
>   - name: Domain
>     paths: [MyApp/Domain/**]
>     allow: [Foundation]
>
>   - name: Data
>     paths: [MyApp/Data/**]
>     deny: [UIKit, SwiftUI]   # Data must never reach into the UI
>
>   - name: Presentation
>     paths: [MyApp/Presentation/**]
>     deny: [NetworkProvider, DataStore]   # UI goes through the Domain, not Data
> ```
>
> Run it against your source tree:
>
> ```bash
> solid-like-a-rock --config .solid.yml MyApp
> ```
>
> If the project already has violations, capture a baseline first so CI only
> fails on *new* ones:
>
> ```bash
> solid-like-a-rock --write-baseline .solid-baseline.json --config .solid.yml MyApp
> solid-like-a-rock --baseline .solid-baseline.json --config .solid.yml MyApp
> ```

## Configure

Create a `.solid.yml` at your project root (or generate one with [`init`](../README.md#generate-a-config-init)) — see the included example:

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
- A file is assigned to the **first** layer whose `paths` glob matches it, so
  list more specific paths first. `paths` are **globs** (`*` within a segment,
  `**` across segments, `?` one char), aligned on path-component boundaries — so
  `Sources/Domain` matches `Sources/Domain/...` but never `Sources/DomainHelpers`.
- **`exclude`** drops any file whose path contains one of these fragments before
  layer matching — essential for monorepos that vendor dependencies (`.build`,
  `Pods`, SwiftPM `checkouts`). You can also pass them on the CLI:
  `solid-like-a-rock --exclude .build Pods -- Sources`.

### Layered mode (`dependencyOrder`)

In a multi-module SPM project a layer often spans several modules. Declare them
with `modules:` (defaults to `[name]`), then declare the layer order **once**
and let the tool derive the rules — no hand-written allow/deny per layer:

```yaml
# innermost first; dependencies may point inward, never outward
dependencyOrder: [Domain, Application, Infrastructure, Presentation]

layers:
  - name: Domain
    modules: [DomainModels, DomainServices]   # one layer, several modules
    paths:   [Sources/Domain/**, Sources/DomainServices/**]

  - name: Presentation
    modules: [UIToolkit, Booking, Search]
    paths:   [Sources/Presentation/**]
    deny:    [NetworkProvider]   # stricter exception on top of the order
```

A module that belongs to a **more-outer** layer than the file's own layer is an
*outward dependency* and fails. Rules resolve in this order:

1. `alwaysAllow` → allowed
2. same layer (intra-layer import) → allowed
3. explicit **`deny`** → violation (forces it, even on an inward import);
   explicit **`allow`** → allowed (exempts it, even from an outward violation)
4. `dependencyOrder`: importing a more-outer layer → violation
5. a module in no layer (third-party framework) → allowed by default

`allow`/`deny` keep working on their own when `dependencyOrder` is unset (the
v0.1.0 behaviour), so existing configs are unchanged. A module may belong to at
most one layer, and every `dependencyOrder` name must match a declared layer —
both are checked before linting.

### Visibility rule (`visibility`)

Opt-in: flag top-level `public`/`open` declarations living in **leaf modules**
— local modules that no other module imports. Either the module is a product
for external consumers (exclude it) or those symbols should be `internal`:

```yaml
visibility:
  warnPublicInLeafModules: true
  excludeModules: [MyPublicSDK]   # vended to external consumers — skipped
  severity: warning               # default; set `error` to fail the build
```

```
Sources/Utils/Helper.swift:1: warning: SolidLikeARock: module 'Utils' is not imported by any other module, but declares public symbol 'Helper' — make it internal, or exclude the module
```

Module-level only, by design: deciding whether a *specific* public symbol is
unused requires type information — that's [Periphery](https://github.com/peripheryapp/periphery)'s
job. Executable modules (`main.swift` / `@main`) are skipped automatically,
and violations are baselineable like any other.

### Security checks (`security`)

Opt-in: 14 rules across **Keychain / Crypto / Network / Auth / Logging**, all
matched on the syntax tree like everything else. Provable patterns default to
`error`, heuristics to `warning`:

```yaml
security:
  enabled: true

  # Optional: override every rule's default severity.
  # severity: warning

  # Optional: turn rules off entirely.
  # disable: [highEntropySecret]

  # Optional: tune one rule.
  # rules:
  #   printSensitiveData:
  #     severity: error
```

Severity resolves in three steps: every rule has a built-in default (`error`
for provable patterns, `warning` for heuristics); a global `security.severity`
overrides all of them; a per-rule `rules.<id>.severity` overrides both.
`disable: [ruleID]` turns a rule off entirely. Unknown rule IDs anywhere in the
config are rejected before linting.

| Rule | Category | Default | Detects |
|------|----------|---------|---------|
| [`keychainAccessibleAlways`](security-rules.md#keychainaccessiblealways-error) | Keychain | error | `kSecAttrAccessibleAlways(ThisDeviceOnly)` — item readable while the device is locked |
| [`keychainMissingAccessibility`](security-rules.md#keychainmissingaccessibility-error) | Keychain | error | `SecItemAdd` query with `kSecClass` but no `kSecAttrAccessible` (or `kSecAttrAccessControl`) |
| [`insecureHash`](security-rules.md#insecurehash-error) | Crypto | error | `Insecure.MD5` / `Insecure.SHA1` (CryptoKit), `CC_MD5` / `CC_SHA1` |
| [`hardcodedSecret`](security-rules.md#hardcodedsecret-error) | Crypto | error | secret-named identifier (`apiKey`, `password`, `token`, …) assigned a non-placeholder literal |
| [`cleartextHTTP`](security-rules.md#cleartexthttp-error) | Network | error | `Info.plist` with `NSAllowsArbitraryLoads = true` (ATS off globally) |
| [`disabledTLSValidation`](security-rules.md#disabledtlsvalidation-error) | Network | error | URLSession challenge handler passing the server trust to `.useCredential` without `SecTrustEvaluate` (trust-all) |
| [`tokenInUserDefaults`](security-rules.md#tokeninuserdefaults-error) | Auth | error | credential-keyed `UserDefaults.set` (`token`, `jwt`, `password`, `secret`, `credential`) |
| [`biometryNoErrorHandling`](security-rules.md#biometrynoerrorhandling-error) | Auth | error | `canEvaluatePolicy(_, error: nil)` — the failure reason is discarded |
| [`publicPIIInLog`](security-rules.md#publicpiiinlog-error) | Logging | error | `\(x, privacy: .public)` interpolation of a PII-named value — os_log redaction defeated |
| [`printSensitiveData`](security-rules.md#printsensitivedata-warning) | Logging | warning | `print` / `NSLog` / `debugPrint` / `dump` of sensitive-named identifiers |
| [`httpURLLiteral`](security-rules.md#httpurlliteral-warning) | Network | warning | `http://` literals (loopback / `.local` / XML-namespace hosts exempt) |
| [`biometryNoFallback`](security-rules.md#biometrynofallback-warning) | Auth | warning | `.deviceOwnerAuthenticationWithBiometrics` — no passcode fallback |
| [`sensitiveDataInUserDefaults`](security-rules.md#sensitivedatainuserdefaults-warning) | Keychain | warning | PII-keyed `UserDefaults.set` (`firstName`, `homeAddress`, `ssn`, …) |
| [`highEntropySecret`](security-rules.md#highentropysecret-warning) | Crypto | warning | long high-entropy base64/hex literals that look like an embedded key |

Each rule is documented in detail — what fires, why it matters, and what is
deliberately not flagged — in the [security rules reference](security-rules.md).

`// solid:ignore <reason>` works on a flagged line (or the line above) exactly
as it does for import violations — the reason is mandatory.

The section is fully standalone: `layers:` is optional, so a config containing
nothing but `security:` with `enabled: true` is valid — that's what
[`init --security`](../README.md#generate-a-config-init) generates on a project without a
config. (A config with nothing to check at all — no layers, no security, no
visibility — is rejected with an explicit error.) A ready-to-use preset lives
at [`examples/security.solid.yml`](../examples/security.solid.yml).
