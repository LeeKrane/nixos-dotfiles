#!/usr/bin/env bash
# Bumps pkgs/claude-code/manifest.zst.json to a claude-code release,
# newest by default, or the version given as $1. Nothing else in the
# flake moves. Review the diff, then `just switch <host>`.
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

# Refuse a manifest that does not describe the version we asked for,
# rather than leaving a mismatched file behind.
NEW="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["version"])' "$MANIFEST")"
if [ "$NEW" != "$VERSION" ]; then
    echo "manifest reports $NEW, expected $VERSION; reverting" >&2
    git -C "$(dirname "$MANIFEST")" checkout -- "$MANIFEST"
    exit 1
fi

echo "claude-code $OLD -> $NEW"
