#!/usr/bin/env bash
# Run: nix shell nixpkgs#jq nixpkgs#gawk --command bash scripts/tests/collapse-hosts-test.sh
set -euo pipefail

SCRIPTS="$(dirname "$(readlink -f "$0")")/.."
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
failures=0
check() {
    local name=$1
    shift
    if "$@"; then echo "ok   $name"; else echo "FAIL $name"; failures=$((failures + 1)); fi
}
ROLES='{"taractias":"desktop","tariognatha":"desktop","tarmantria":"desktop","taragarmr":"server","taronychus":"server","tarritator":"server","tarronax":"server"}'
collapse() {
    jq -rn -L "$SCRIPTS/lib" --argjson roles "$ROLES" --argjson h "$1" \
        'include "collapse-hosts"; $h | collapse_hosts($roles)' 2>/dev/null || echo ERROR
}

check 'all hosts' [ "$(collapse '["taractias","tariognatha","tarmantria","taragarmr","taronychus","tarritator","tarronax"]')" = all ]
check 'servers' [ "$(collapse '["taragarmr","taronychus","tarritator","tarronax"]')" = servers ]
check 'desktops' [ "$(collapse '["tarmantria","taractias","tariognatha"]')" = desktops ]
check 'servers plus two desktops' [ "$(collapse '["taragarmr","taronychus","tarritator","tarronax","tariognatha","tarmantria"]')" = 'servers, tariognatha, tarmantria' ]
check 'single hosts only' [ "$(collapse '["taragarmr","taractias"]')" = 'taragarmr, taractias' ]
check 'empty list' [ "$(collapse '[]')" = '' ]

echo '{"nodes":{"root":{"inputs":{}}},"root":"root","version":7}' >"$WORK/lock.json"
jq -n '{taragarmr:{p:"1"},taronychus:{p:"1"},tarritator:{p:"1"},tarronax:{p:"1"},taractias:{p:"1"},tariognatha:{p:"1"},tarmantria:{p:"1"}}' >"$WORK/before.json"
jq -n '{taragarmr:{p:"2"},taronychus:{p:"2"},tarritator:{p:"2"},tarronax:{p:"2"},taractias:{p:"3"},tariognatha:{p:"1"},tarmantria:{p:"1"}}' >"$WORK/after.json"
with="$(HOST_ROLES="$ROLES" bash "$SCRIPTS/update-summary.sh" "$WORK/lock.json" "$WORK/lock.json" "$WORK/before.json" "$WORK/after.json" 2>&1 || true)"
without="$(bash "$SCRIPTS/update-summary.sh" "$WORK/lock.json" "$WORK/lock.json" "$WORK/before.json" "$WORK/after.json" 2>&1 || true)"
check 'update-summary: collapsed row' grep -qF '| p | 1 | 2 | servers |' <<<"$with"
check 'update-summary: no HOST_ROLES keeps join' grep -qF '| p | 1 | 2 | taragarmr, taronychus, tarritator, tarronax |' <<<"$without"

jq -n '{taragarmr:{p:"1"},taronychus:{p:"1"},tarritator:{p:"1"},tarronax:{p:"1"}}' >"$WORK/srv-before.json"
jq -n '{taragarmr:{p:"2"},taronychus:{p:"2"},tarritator:{p:"2"},tarronax:{p:"2"}}' >"$WORK/srv-after.json"
uniform="$(HOST_ROLES="$ROLES" bash "$SCRIPTS/update-summary.sh" "$WORK/lock.json" "$WORK/lock.json" "$WORK/srv-before.json" "$WORK/srv-after.json" 2>&1 || true)"
check 'update-summary: uniform servers row shows hosts' grep -qF '| p | 1 | 2 | servers |' <<<"$uniform"
check 'update-summary: uniform servers has Hosts header' grep -qF '| Package | Before | After | Hosts |' <<<"$uniform"
jq '. + {taractias:{p:"1"},tariognatha:{p:"1"},tarmantria:{p:"1"}}' "$WORK/srv-before.json" >"$WORK/all-before.json"
jq '. + {taractias:{p:"2"},tariognatha:{p:"2"},tarmantria:{p:"2"}}' "$WORK/srv-after.json" >"$WORK/all-after.json"
everywhere="$(HOST_ROLES="$ROLES" bash "$SCRIPTS/update-summary.sh" "$WORK/lock.json" "$WORK/lock.json" "$WORK/all-before.json" "$WORK/all-after.json" 2>&1 || true)"
check 'update-summary: change on every host shows all' grep -qF '| p | 1 | 2 | all |' <<<"$everywhere"
plain="$(bash "$SCRIPTS/update-summary.sh" "$WORK/lock.json" "$WORK/lock.json" "$WORK/srv-before.json" "$WORK/srv-after.json" 2>&1 || true)"
check 'update-summary: no HOST_ROLES uniform keeps 3 columns' grep -qF '| p | 1 | 2 |' <<<"$plain"
# shellcheck disable=SC2016 # eval expands it, on purpose
check 'update-summary: no HOST_ROLES uniform has no Hosts header' eval '! grep -qF "| Hosts |" <<<"$plain"'

mkdir -p "$WORK/sec"
servers=(taragarmr taronychus tarritator tarronax)
for h in "${servers[@]}"; do
    echo '[]' >"$WORK/sec/vulnix-before-$h.json"
    echo '[{"pname":"openssl","version":"3.0","affected_by":["CVE-2026-0001"],"cvssv3_basescore":{"CVE-2026-0001":9.8}}]' \
        >"$WORK/sec/vulnix-after-$h.json"
done
sec_with="$(HOST_ROLES="$ROLES" bash "$SCRIPTS/security-summary.sh" "$WORK/sec" "${servers[@]}" 2>&1 || true)"
sec_without="$(bash "$SCRIPTS/security-summary.sh" "$WORK/sec" "${servers[@]}" 2>&1 || true)"
check 'security-summary: collapsed hosts' grep -q 'CVE-2026-0001.*| servers |$' <<<"$sec_with"
check 'security-summary: no HOST_ROLES keeps all' grep -q 'CVE-2026-0001.*| all |$' <<<"$sec_without"

[ "$failures" -eq 0 ] || { echo "$failures failure(s)"; exit 1; }
