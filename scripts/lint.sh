#!/usr/bin/env bash
# The lint checks, one source of truth for CI (.github/workflows/check.yml) and
# the pre-push hook (.githooks/pre-push). Tools come from the flake's pinned
# nixpkgs, like CI.
set -euo pipefail

cd "$(dirname "$(readlink -f "$0")")/.."
nixsh() { nix shell --inputs-from . "$@"; }

echo "== nixfmt"
nix fmt -- --ci
echo "== statix"
nixsh nixpkgs#statix -c statix check .
echo "== deadnix"
nixsh nixpkgs#deadnix -c deadnix --fail --exclude hosts/*/hardware-configuration.nix -- .
echo "== shellcheck"
nixsh nixpkgs#shellcheck -c shellcheck -x -S style install.sh scripts/*.sh scripts/tests/*.sh scripts/ii-agents/*.sh
echo "== actionlint"
# With shellcheck on PATH, actionlint also checks every inline `run:` block.
nixsh nixpkgs#actionlint nixpkgs#shellcheck -c actionlint
echo "== secrets encrypted"
bash scripts/check-secrets-encrypted.sh
