#!/usr/bin/env bash
# Tests scripts/lib/collapse-hosts.jq and its use in update-summary.sh and security-summary.sh. Run:
#   nix shell nixpkgs#jq nixpkgs#gawk --command bash scripts/tests/collapse-hosts-test.sh
set -euo pipefail

SCRIPTS="$(dirname "$(readlink -f "$0")")/.."
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
failures=0
check() { # check NAME CONDITION...
    local name=$1
    shift
    if "$@"; then echo "ok   $name"; else echo "FAIL $name"; failures=$((failures + 1)); fi
}
ROLES='{"taractias":"desktop","tariognatha":"desktop","tarmantria":"desktop","taragarmr":"server","taronychus":"server","tarritator":"server","tarronax":"server"}'
collapse() { # collapse JSON_ARRAY
    jq -rn -L "$SCRIPTS/lib" --argjson roles "$ROLES" --argjson h "$1" \
        'include "collapse-hosts"; $h | collapse_hosts($roles)' 2>/dev/null || echo ERROR
}

check 'all hosts' [ "$(collapse '["taractias","tariognatha","tarmantria","taragarmr","taronychus","tarritator","tarronax"]')" = all ]
check 'servers' [ "$(collapse '["taragarmr","taronychus","tarritator","tarronax"]')" = servers ]
check 'desktops' [ "$(collapse '["tarmantria","taractias","tariognatha"]')" = desktops ]
check 'servers plus two desktops' [ "$(collapse '["taragarmr","taronychus","tarritator","tarronax","tariognatha","tarmantria"]')" = 'servers, tariognatha, tarmantria' ]
check 'single hosts only' [ "$(collapse '["taragarmr","taractias"]')" = 'taragarmr, taractias' ]
check 'empty list' [ "$(collapse '[]')" = '' ]

# update-summary.sh: a split version row names its hosts collapsed when HOST_ROLES is set,
# and plainly joined when it is not.
echo '{"nodes":{"root":{"inputs":{}}},"root":"root","version":7}' >"$WORK/lock.json"
jq -n '{taragarmr:{p:"1"},taronychus:{p:"1"},tarritator:{p:"1"},tarronax:{p:"1"},taractias:{p:"1"},tariognatha:{p:"1"},tarmantria:{p:"1"}}' >"$WORK/before.json"
jq -n '{taragarmr:{p:"2"},taronychus:{p:"2"},tarritator:{p:"2"},tarronax:{p:"2"},taractias:{p:"3"},tariognatha:{p:"1"},tarmantria:{p:"1"}}' >"$WORK/after.json"
with="$(HOST_ROLES="$ROLES" bash "$SCRIPTS/update-summary.sh" "$WORK/lock.json" "$WORK/lock.json" "$WORK/before.json" "$WORK/after.json" 2>&1 || true)"
without="$(bash "$SCRIPTS/update-summary.sh" "$WORK/lock.json" "$WORK/lock.json" "$WORK/before.json" "$WORK/after.json" 2>&1 || true)"
check 'update-summary: collapsed row' grep -qF '| p | 1 | 2 | servers |' <<<"$with"
check 'update-summary: no HOST_ROLES keeps join' grep -qF '| p | 1 | 2 | taragarmr, taronychus, tarritator, tarronax |' <<<"$without"

# security-summary.sh: a CVE new on all four scanned servers is "servers" with HOST_ROLES
# (collapsed against the whole flake) and "all" without it (every scanned host).
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
