#!/usr/bin/env bash
# Tests scripts/check-secrets-encrypted.sh against fixture secrets dirs. Run:
#   bash scripts/tests/check-secrets-encrypted-test.sh
set -euo pipefail

ROOT="$(dirname "$(readlink -f "$0")")/../.."
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
failures=0
check() { # check NAME CONDITION...
    local name=$1
    shift
    if "$@"; then echo "ok   $name"; else echo "FAIL $name"; failures=$((failures + 1)); fi
}
guard() { bash "$ROOT/scripts/check-secrets-encrypted.sh" "$1" >/dev/null 2>&1; }

mkdir "$WORK/good" "$WORK/bad"
printf 'key: ENC[AES256_GCM,data:x]\nsops:\n    version: 3.9.0\n' >"$WORK/good/a.yaml"
printf 'key: ENC[AES256_GCM,data:x]\nsops:\n    version: 3.9.0\n' >"$WORK/good/b.yaml"
check 'encrypted files pass' guard "$WORK/good"

printf 'key: hunter2\n' >"$WORK/bad/a.yaml"
printf 'key: ENC[AES256_GCM,data:x]\nsops:\n    version: 3.9.0\n' >"$WORK/bad/b.yaml"
check 'plaintext file fails' eval "! guard '$WORK/bad'"

# An indented or commented "sops:" is not a top-level key.
printf 'a:\n    sops: x\n# sops:\n' >"$WORK/bad/a.yaml"
check 'nested sops key fails' eval "! guard '$WORK/bad'"

check 'real secrets pass' guard "$ROOT/secrets"

[ "$failures" -eq 0 ]
