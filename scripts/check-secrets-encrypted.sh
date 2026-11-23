#!/usr/bin/env bash
# Fails if any secrets/*.yaml lacks a top-level `sops:` key (an accidentally
# decrypted file). Usage: check-secrets-encrypted.sh [SECRETS_DIR]
set -euo pipefail

dir="${1:-$(dirname "$(readlink -f "$0")")/../secrets}"
status=0
for f in "$dir"/*.yaml; do
    [ -e "$f" ] || continue
    if ! grep -q '^sops:' "$f"; then
        echo "not encrypted (no top-level sops: key): $f" >&2
        status=1
    fi
done
exit "$status"
