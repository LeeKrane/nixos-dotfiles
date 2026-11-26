#!/usr/bin/env bash
# Usage: update-claude-code.sh [VERSION]; bumps pkgs/claude-code/manifest.zst.json, newest by default.
set -euo pipefail

BASE_URL="https://downloads.claude.ai/claude-code-releases"
MANIFEST="$(dirname "$(dirname "$(readlink -f "$0")")")/pkgs/claude-code/manifest.zst.json"

VERSION="${1:-$(curl -fsSL "$BASE_URL/latest")}"
OLD="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["version"])' "$MANIFEST")"

if [ "$VERSION" = "$OLD" ]; then
    echo "claude-code already at $OLD"
    exit 0
fi

curl -fsSL "$BASE_URL/$VERSION/manifest.zst.json" --output "$MANIFEST"

NEW="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["version"])' "$MANIFEST")"
if [ "$NEW" != "$VERSION" ]; then
    echo "manifest reports $NEW, expected $VERSION; reverting" >&2
    git -C "$(dirname "$MANIFEST")" checkout -- "$MANIFEST"
    exit 1
fi

echo "claude-code $OLD -> $NEW"
