# Adopting on a living codebase

Three features make it realistic to switch the linter on for a project that
already has violations, without fixing everything on day one. New here? Start
with the [README](../README.md).

## Baseline — fail only on *new* violations

Record the current violations once, then have CI fail only on ones introduced
afterwards:

```bash
# snapshot today's violations (run once, commit the file)
solid-like-a-rock --write-baseline .solid-baseline.json Sources

# from now on, only NEW violations are reported and fail the build
solid-like-a-rock --baseline .solid-baseline.json Sources
```

A violation's identity is `file + module + reason` — the line number is
excluded, so editing code above an import doesn't resurface a baselined entry as
"new". The baseline file is plain, sorted JSON: diff-friendly and safe to commit.

<p align="center">
  <img src="../demo/baseline.gif" alt="Demo: existing violations are recorded in a baseline, then lint passes — only new violations fail" width="720">
</p>

## Inline suppressions — `// solid:ignore <reason>`

For a deliberate, justified exception, annotate the import. The **reason is
mandatory** (a bare `// solid:ignore` does nothing):

```swift
import UIKit // solid:ignore needed for the legacy bridge, removed in #1234
```

The directive also works on the line directly above the import. SolidLikeARock
reads it from the syntax tree's trivia, so it's matched on the real `import`, not
by text scanning.

## Severity — warn without failing the build

Give a layer `severity: warning` to surface its violations as warnings (reported,
but the build still passes). Default is `error`.

```yaml
layers:
  - name: Presentation
    paths: [Sources/Presentation/**]
    deny: [NetworkProvider]
    severity: warning      # report, don't fail (yet)
```

Diagnostics use the matching keyword (`… warning: …` / `… error: …`), and the
process exits non-zero only when at least one **error**-level violation remains.
