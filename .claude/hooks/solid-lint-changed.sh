#!/usr/bin/env bash
#
# solid-like-a-rock — Claude Code PostToolUse hook
#
# Runs the architecture linter after Claude edits a Swift file, and feeds any
# violations back to the agent so it fixes the boundary instead of moving on.
# This is the "guardrail for AI-assisted development": the agent doesn't decide
# whether to run the linter — the harness runs it automatically.
#
# Wire it via .claude/settings.json:
#   "hooks": { "PostToolUse": [ { "matcher": "Edit|Write|MultiEdit",
#     "hooks": [ { "type": "command",
#       "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/solid-lint-changed.sh" } ] } ] }
#
# Behaviour:
#   - non-.swift edit, no .solid.yml found, or linter not installed → exit 0 (silent no-op)
#   - violations found → print them on stderr, exit 2 (Claude sees them and must fix)
#
# The linter binary is `solid-like-a-rock` on PATH (Homebrew/SPI). Override with
# $SOLID_BIN, e.g. SOLID_BIN="swift run solid-like-a-rock" for a from-source repo.
set -euo pipefail

SOLID_BIN="${SOLID_BIN:-solid-like-a-rock}"

# 1. Read the hook payload and pull out the edited file path.
payload="$(cat)"
file="$(printf '%s' "$payload" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)"

# 2. Only react to Swift source edits.
case "$file" in
  *.swift) ;;
  *) exit 0 ;;
esac

# 3. Walk up from the edited file to find the nearest .solid.yml (the project root).
dir="$(cd "$(dirname "$file")" 2>/dev/null && pwd || true)"
config=""
while [ -n "$dir" ] && [ "$dir" != "/" ]; do
  if [ -f "$dir/.solid.yml" ]; then config="$dir/.solid.yml"; break; fi
  dir="$(dirname "$dir")"
done
[ -n "$config" ] || exit 0   # project doesn't use solid-like-a-rock → nothing to do

# 4. The linter must be available, otherwise stay out of the way.
command -v ${SOLID_BIN%% *} >/dev/null 2>&1 || exit 0

# 5. Lint the project. Prefer Sources/ if present; the config's `exclude` keeps
#    build artefacts out either way.
root="$(dirname "$config")"
target="$root"; [ -d "$root/Sources" ] && target="$root/Sources"

if output="$($SOLID_BIN --config "$config" "$target" 2>&1)"; then
  exit 0   # clean
fi

# 6. Violations: hand them to the agent and block completion (exit 2).
{
  echo "solid-like-a-rock found architecture violations after your edit to ${file#"$root"/}:"
  echo
  echo "$output"
  echo
  echo "Fix the boundary, do not relax the rule. Prefer (in order):"
  echo "  1. Remove the offending import if it is unused."
  echo "  2. Move shared code to an inner layer both sides may import (dependencies point inward)."
  echo "  3. Depend on an interface and inject the implementation at the composition root."
  echo "Only as a last resort, with a justification, add '// solid:ignore <reason>' or a config exception."
} >&2
exit 2
