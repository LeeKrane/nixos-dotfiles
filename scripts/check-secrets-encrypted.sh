#!/usr/bin/env bash
# Usage: check-secrets-encrypted.sh [SECRETS_DIR]
set -euo pipefail

dir="${1:-$(dirname "$(readlink -f "$0")")/../secrets}"
status=0
for f in "$dir"/*.yaml; do
    [ -e "$f" ] || continue
    if ! grep -q '^sops:' "$f"; then
        echo "not encrypted (no top-level sops: key): $f" >&2
        status=1
        continue
    fi
    bad=$(awk '
        /^[[:space:]]*(#|$)/ { next }
        /^sops:/ { insops = 1; next }
        insops && /^[^[:space:]]/ { insops = 0 }
        insops { next }
        /^[[:space:]]*(- )?[^:#]+:[[:space:]]*$/ { next }
        /^[[:space:]]*(- )?[^:#]+:[[:space:]]+ENC\[/ { next }
        /^[[:space:]]*- ENC\[/ { next }
        { print FILENAME ":" NR }
    ' "$f")
    if [ -n "$bad" ]; then
        echo "unencrypted value at: $bad" >&2
        status=1
    fi
done
exit "$status"
