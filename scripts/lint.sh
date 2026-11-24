#!/usr/bin/env bash
# The lint checks, one source of truth for CI (.github/workflows/check.yml) and
# the pre-push hook (.githooks/pre-push). Tools come from the flake's pinned
# nixpkgs, like CI.
set -euo pipefail

cd "$(dirname "$(readlink -f "$0")")/.."
nixsh() { nix shell --inputs-from . "$@"; }

# Every check runs even after one fails, so one run reports all findings.
failed=()
step() {
    local name=$1
    shift
    echo "== $name"
    "$@" || failed+=("$name")
}

step nixfmt nix fmt -- --ci
step statix nixsh nixpkgs#statix -c statix check .
step deadnix nixsh nixpkgs#deadnix -c deadnix --fail --exclude hosts/*/hardware-configuration.nix -- .
step shellcheck nixsh nixpkgs#shellcheck -c shellcheck -x -S style install.sh scripts/*.sh scripts/tests/*.sh scripts/ii-agents/*.sh
# With shellcheck on PATH, actionlint also checks every inline `run:` block.
step actionlint nixsh nixpkgs#actionlint nixpkgs#shellcheck -c actionlint
# gawk from the flake: the docker lint container has no awk.
step "secrets encrypted" nixsh nixpkgs#gawk -c bash scripts/check-secrets-encrypted.sh

if [ "${#failed[@]}" -gt 0 ]; then
    echo "lint failed: ${failed[*]}" >&2
    exit 1
fi
