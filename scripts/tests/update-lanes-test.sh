#!/usr/bin/env bash
# Run: nix shell nixpkgs#jq --command bash scripts/tests/update-lanes-test.sh
set -euo pipefail

ROOT="$(dirname "$(readlink -f "$0")")/../.."
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
failures=0
check() {
    local name=$1
    shift
    if "$@"; then echo "ok   $name"; else echo "FAIL $name"; failures=$((failures + 1)); fi
}
lanes() {
    nix eval --json --impure --expr \
        "import $ROOT/scripts/update-lanes.nix (builtins.fromJSON (builtins.readFile $1))"
}

jq -n '{root: "root", version: 7, nodes: {root: {inputs: {
    "nixos-raspberrypi": "nixos-raspberrypi", "home-manager-stable": "home-manager-stable",
    "nixvim-stable": "nixvim-stable", "sops-nix": "sops-nix", "disko": "disko",
    "nix-index-database": "nix-index-database", "nixpkgs": "nixpkgs_5", "zen-browser": "zen-browser",
    "nixpkgs-stable": ["nixos-raspberrypi", "nixpkgs"]}}}}' >"$WORK/lock.json"
out="$(lanes "$WORK/lock.json" || true)"
check 'fixture: servers' [ "$(jq -c '.servers | sort' <<<"$out" 2>/dev/null)" = '["disko","home-manager-stable","nix-index-database","nixos-raspberrypi","nixvim-stable","sops-nix"]' ]
check 'fixture: desktops' [ "$(jq -c '.desktops | sort' <<<"$out" 2>/dev/null)" = '["nixpkgs","zen-browser"]' ]
check 'fixture: follows input in no lane' [ "$(jq '[.servers[], .desktops[]] | index("nixpkgs-stable")' <<<"$out" 2>/dev/null)" = null ]

jq 'del(.nodes.root.inputs.disko)' "$WORK/lock.json" >"$WORK/lock-nodisko.json"
# shellcheck disable=SC2016 # eval expands it, on purpose
check 'missing server input: eval fails' eval '! lanes "$WORK/lock-nodisko.json" >/dev/null 2>&1'

real="$(lanes "$ROOT/flake.lock" || true)"
roots="$(jq -c '[.nodes[.root].inputs | to_entries[] | select(.value | type == "string") | .key] | sort' "$ROOT/flake.lock")"
check 'real: union is every updatable root' [ "$(jq -c '[.servers[], .desktops[]] | sort' <<<"$real" 2>/dev/null)" = "$roots" ]
check 'real: no overlap' [ "$(jq '[.servers[] as $s | .desktops | index($s)] | map(select(. != null)) | length' <<<"$real" 2>/dev/null)" = 0 ]

[ "$failures" -eq 0 ] || { echo "$failures failure(s)"; exit 1; }
