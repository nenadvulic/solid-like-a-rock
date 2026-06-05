# Demo tapes

Terminal demos recorded with [vhs](https://github.com/charmbracelet/vhs). Each
tape is a script: the GIFs are fully reproducible and can be re-rendered after
any release so they never go stale.

| Tape | GIF | Shows |
|------|-----|-------|
| `demo.tape` | `demo.gif` | The pitch: a forbidden import → ❌ → fix → ✅ |
| `init-freeze.tape` | `init-freeze.gif` | `init --freeze`: adopt on an existing codebase with zero violations, bites on new cross-module deps |
| `baseline.tape` | `baseline.gif` | `--write-baseline` / `--baseline`: only new violations fail |
| `linkedin.tape` | `linkedin.mp4` (not committed) | Social cut of the pitch: square 1080×1080 native video, large font, ~35s |

## Re-render

```bash
brew install vhs
brew install solid-like-a-rock   # or have it on PATH

cd demo
vhs demo.tape
vhs init-freeze.tape
vhs baseline.tape
```

Each tape contains hidden setup/teardown steps that (re)plant or clean up the
violation in its fixture, so recordings are idempotent — run them as many
times as you like.

## Fixtures

- `fixture/` — three-layer sample project used by `demo.tape` and
  `baseline.tape`. Its committed state contains one deliberate violation
  (`import Data` in the Presentation layer).
- `fixture-init/` — clean multi-module sample used by `init-freeze.tape`; the
  tape generates `.solid.yml` on camera and removes it afterwards.
