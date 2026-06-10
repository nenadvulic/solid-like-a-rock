# solid-like-a-rock — Claude Code integration

Runs the architecture linter automatically when an AI agent edits Swift code, so
boundary violations get caught and fixed in the same turn the agent introduces
them — the agent never decides whether to check.

## Files

| File | Role |
|------|------|
| `hooks/solid-lint-changed.sh` | PostToolUse hook: lints the project after a `.swift` edit |
| `settings.json` | Wires the hook to `Edit\|Write\|MultiEdit` |

To adopt in another project, copy both files into its `.claude/` directory.

## Activate

Claude Code only watches `.claude/settings.json` files that existed when the
session started. After copying the files into a running session, open `/hooks`
once (or restart Claude Code) so the hook is loaded. New sessions pick it up
automatically.

## What the agent sees on a violation

The hook lints, then exits non-zero so the diagnostics are fed back to the agent:

```
solid-like-a-rock found architecture violations after your edit to Sources/LoginFeature/LoginFeature.swift:

Sources/LoginFeature/LoginFeature.swift:3: error: SolidLikeARock: layer 'Features' has isolatePeers enabled — must not import peer module 'CounterFeature'
❌ SolidLikeARock: 1 error(s), 0 warning(s).

Fix the boundary, do not relax the rule. Prefer (in order):
  1. Remove the offending import if it is unused.
  2. Move shared code to an inner layer both sides may import (dependencies point inward).
  3. Depend on an interface and inject the implementation at the composition root.
Only as a last resort, with a justification, add '// solid:ignore <reason>' or a config exception.
```

It is a silent no-op when the edited file is not Swift, no `.solid.yml` is found
by walking up from the file, or the linter is not installed — so it never blocks
unrelated work.

## Choosing the binary (`SOLID_BIN`)

By default the hook calls `solid-like-a-rock` on `PATH` (Homebrew / Swift Package
Index). Override it for a project that runs the tool differently — for example a
checkout with no installed binary:

```bash
# in settings.json, set an env var for the command, or export it in your shell:
SOLID_BIN="swift run --package-path /path/to/solid-like-a-rock solid-like-a-rock"
```

## Alternative: a Stop hook (lint once, at the end)

The PostToolUse hook above lints after *every* Swift edit — immediate feedback,
but it runs repeatedly during a multi-file change. If you prefer a single check
right before the agent finishes its turn, use a `Stop` hook instead. It lints the
whole project once; on a violation, exit 2 keeps the agent working until it's
clean.

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          { "type": "command", "command": "solid-like-a-rock 1>&2 || exit 2" }
        ]
      }
    ]
  }
}
```

Trade-off: PostToolUse catches the violation at the moment it's introduced (easier
to attribute); Stop checks less often but only when the agent thinks it's done.
Pick one — running both just double-reports.
