#!/usr/bin/env bash
#
# Assemble a SwiftPM .artifactbundle around the release binary, so the build-tool
# plugin can use a prebuilt executable (prebuild commands can't build from source).
#
# Usage: scripts/make-artifactbundle.sh <version> [output-dir]
#   version    e.g. 0.4.0 (no leading v)
#   output-dir where the .artifactbundle is written (default: repo root)

set -euo pipefail

VERSION="${1:?usage: make-artifactbundle.sh <version> [output-dir]}"
OUT_DIR="${2:-.}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

swift build -c release --product solid-like-a-rock --package-path "$ROOT"
BIN="$ROOT/.build/release/solid-like-a-rock"
test -x "$BIN"

BUNDLE="$OUT_DIR/solid-like-a-rock.artifactbundle"
VARIANT="solid-like-a-rock-$VERSION-macos"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/$VARIANT/bin"
cp "$BIN" "$BUNDLE/$VARIANT/bin/solid-like-a-rock"

cat > "$BUNDLE/info.json" <<JSON
{
  "schemaVersion" : "1.0",
  "artifacts" : {
    "solid-like-a-rock" : {
      "version" : "$VERSION",
      "type" : "executable",
      "variants" : [
        {
          "path" : "$VARIANT/bin/solid-like-a-rock",
          "supportedTriples" : [ "arm64-apple-macosx", "x86_64-apple-macosx" ]
        }
      ]
    }
  }
}
JSON

echo "✓ built $BUNDLE (version $VERSION)"
