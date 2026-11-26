#!/usr/bin/env bash
# Run: nix shell nixpkgs#jq --command bash scripts/tests/update-select-lanes-test.sh
set -euo pipefail

SCRIPT="$(dirname "$(readlink -f "$0")")/../update-select-lanes.sh"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin" "$WORK/fix"
failures=0
check() {
    local name=$1
    shift
    if "$@"; then echo "ok   $name"; else echo "FAIL $name"; failures=$((failures + 1)); fi
}

command cat >"$WORK/bin/gh" <<'EOF'
#!/usr/bin/env bash
head="" expr="."
while [ "$#" -gt 0 ]; do
    case "$1" in
        --head) head="$2"; shift 2 ;;
        --jq) expr="$2"; shift 2 ;;
        *) shift ;;
    esac
done
f="$FIX/${head//\//_}.json"
[ -f "$f" ] || { jq -r "$expr" <<<'[]'; exit 0; }
n=$(( $(command cat "$f.calls" 2>/dev/null || echo 0) + 1 ))
echo "$n" >"$f.calls"
total=$(wc -l <"$f")
[ "$n" -le "$total" ] || n=$total
sed -n "${n}p" "$f" | jq -r "$expr"
EOF
printf '#!/usr/bin/env bash\nexit 0\n' >"$WORK/bin/sleep"
chmod +x "$WORK/bin/gh" "$WORK/bin/sleep"

pr() {
    jq -cn --arg m "$1" --argjson x "${2:-false}" '[{mergeable: $m, isCrossRepository: $x}]'
}
run() {
    status=0
    out="$(env PATH="$WORK/bin:$PATH" FIX="$WORK/fix" "$@" bash "$SCRIPT" 2>"$WORK/stderr")" || status=$?
}
reset() { rm -f "$WORK/fix/"*; }

run EVENT=schedule
check 'schedule: both' [ "$out" = '["servers","desktops"]' ]
run EVENT=workflow_dispatch LANE_INPUT=both
check 'dispatch both' [ "$out" = '["servers","desktops"]' ]
run EVENT=workflow_dispatch LANE_INPUT=desktops
check 'dispatch desktops' [ "$out" = '["desktops"]' ]
run EVENT=workflow_dispatch LANE_INPUT=nope
check 'dispatch unknown lane fails' [ "$status" -eq 1 ]
run EVENT=pull_request
check 'unsupported event fails' [ "$status" -eq 1 ]

reset
pr CONFLICTING >"$WORK/fix/ci_flake-update-desktops.json"
pr MERGEABLE >"$WORK/fix/ci_flake-update-servers.json"
run EVENT=push
check 'push: conflicting lane only' [ "$out" = '["desktops"]' ]

reset
run EVENT=push
check 'push: no open PRs' [ "$out" = '[]' ]
check 'push: no open PRs exit 0' [ "$status" -eq 0 ]

reset
{ pr UNKNOWN; pr UNKNOWN; pr CONFLICTING; } >"$WORK/fix/ci_flake-update-servers.json"
run EVENT=push
check 'push: UNKNOWN then CONFLICTING' [ "$out" = '["servers"]' ]

reset
pr UNKNOWN >"$WORK/fix/ci_flake-update-servers.json"
run EVENT=push POLL_INTERVAL=10 POLL_DEADLINE=30
check 'push: UNKNOWN until deadline selects nothing' [ "$out" = '[]' ]
check 'push: UNKNOWN until deadline exit 0' [ "$status" -eq 0 ]
check 'push: UNKNOWN until deadline warns' grep -q '::warning::' "$WORK/stderr"
check 'push: polled 4 times' [ "$(command cat "$WORK/fix/ci_flake-update-servers.json.calls" 2>/dev/null)" = 4 ]

reset
pr CONFLICTING true >"$WORK/fix/ci_flake-update-servers.json"
run EVENT=push
check 'push: fork PR ignored' [ "$out" = '[]' ]

[ "$failures" -eq 0 ] || { echo "$failures failure(s)"; exit 1; }
