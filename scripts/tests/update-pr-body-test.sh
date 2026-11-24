#!/usr/bin/env bash
# Tests scripts/update-lane-meta.sh, scripts/update-pr-body.sh and scripts/host-drvs.nix,
# scripts/host-warnings.nix and scripts/lib/warnings-diff.jq. Run:
#   nix shell nixpkgs#jq --command bash scripts/tests/update-pr-body-test.sh
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
has() { grep -qF -- "$1" "$WORK/body.md"; }

# --- update-lane-meta.sh: the one lane table ---------------------------------
meta_servers="$(bash "$SCRIPTS/update-lane-meta.sh" servers 2>/dev/null || true)"
meta_desktops="$(bash "$SCRIPTS/update-lane-meta.sh" desktops 2>/dev/null || true)"
check 'meta servers: title' grep -qx 'title=Update server inputs' <<<"$meta_servers"
check 'meta servers: commit' grep -qx 'commit=Update server inputs and claude-code' <<<"$meta_servers"
check 'meta servers: claude-code' grep -qx 'claude_code=true' <<<"$meta_servers"
check 'meta servers: switch host' grep -qx 'switch_host=taragarmr' <<<"$meta_servers"
check 'meta desktops: title' grep -qx 'title=Update desktop inputs' <<<"$meta_desktops"
check 'meta desktops: commit' grep -qx 'commit=Update desktop inputs' <<<"$meta_desktops"
check 'meta desktops: no claude-code' grep -qx 'claude_code=false' <<<"$meta_desktops"
# shellcheck disable=SC2016 # eval expands it, on purpose
check 'meta unknown lane fails' eval '! bash "$SCRIPTS/update-lane-meta.sh" nope >/dev/null 2>&1'

# --- update-pr-body.sh ---------------------------------------------------------
ROLES='{"taractias":"desktop","tariognatha":"desktop","tarmantria":"desktop","taragarmr":"server","taronychus":"server","tarritator":"server","tarronax":"server"}'
echo '### Package versions' >"$WORK/summary.md"
echo '### Security' >"$WORK/security.md"
body() { # body LANE HOSTS [ENV=VAL...]: writes $WORK/body.md, sets $title
    local lane=$1 hosts=$2
    shift 2
    title="$(env LANE="$lane" HOSTS="$hosts" ROLES="$ROLES" RESULT=success SECURITY_RESULT=success \
        RUN_URL=https://run SUMMARY="$WORK/summary.md" SECURITY_SUMMARY="$WORK/security.md" "$@" \
        bash "$SCRIPTS/update-pr-body.sh" "$WORK/body.md" 2>/dev/null || true)"
}

body servers '["taragarmr","taronychus","tarritator","tarronax"]'
check 'servers: title' [ "$title" = 'Update server inputs' ]
check 'servers: deploy banner' has '**Merging deploys to: servers'
check 'servers: summary included' has '### Package versions'
check 'servers: security included' has '### Security'
check 'servers: fetch command' has 'git fetch origin ci/flake-update-servers && git switch -C ci/flake-update-servers FETCH_HEAD'
check 'servers: switch host' has 'just switch taragarmr'

body servers '[]' SECURITY_RESULT=skipped
check 'servers no hosts: no banner' eval '! has "Merging deploys"'
check 'servers no hosts: says so' has 'No host closure changed.'
check 'servers no hosts: no scan failure' eval '! has "Security scan failed"'

body desktops '["taractias","tariognatha","tarmantria"]'
check 'desktops only: no banner' eval '! has "Merging deploys"'
check 'desktops: switch host placeholder' has 'just switch <host>'

body desktops '["taractias","tariognatha","tarmantria","taragarmr"]'
check 'desktops hitting a server: banner names it' has '**Merging deploys to: taragarmr'

body desktops '["taractias"]' RESULT=failure SECURITY_RESULT=failure
check 'gate failing: title prefix' [ "$title" = '[gate failing] Update desktop inputs' ]
check 'gate failing: gate line' has 'Gate: ❌ failing'
check 'security failed: says so' has 'Security scan failed ([run](https://run))'

# --- eval warnings section -----------------------------------------------------
body servers '["taragarmr"]'
check 'no warnings env: no section' eval '! has "Eval warnings"'
echo '{}' >"$WORK/warnings.json"
body servers '["taragarmr"]' WARNINGS="$WORK/warnings.json"
check 'empty warnings: no section' eval '! has "Eval warnings"'

echo '{"taractias":{"new":["a is deprecated"],"existing":[]},"tariognatha":{"new":["a is deprecated"],"existing":["old one"]},"taragarmr":{"new":[],"existing":["old one"]}}' >"$WORK/warnings.json"
body desktops '["taractias","tariognatha","taragarmr"]' WARNINGS="$WORK/warnings.json"
check 'new warnings: section' has '### Eval warnings'
check 'new warnings: shown once for identical hosts' [ "$(grep -cF 'a is deprecated' "$WORK/body.md")" = 1 ]
check 'new warnings: hosts collapsed' has 'New on taractias, tariognatha'
check 'existing warnings: in details' has '<summary>Existing warnings</summary>'
check 'existing warnings: shown once for identical hosts' [ "$(grep -cF 'old one' "$WORK/body.md")" = 1 ]
check 'existing warnings: hosts' has 'tariognatha, taragarmr'

echo '{"taragarmr":{"new":[],"existing":["old one"]}}' >"$WORK/warnings.json"
body servers '["taragarmr"]' WARNINGS="$WORK/warnings.json"
check 'existing only: section' has '### Eval warnings'
check 'existing only: no new list' eval '! has "New on"'
check 'existing only: details' has '<summary>Existing warnings</summary>'

echo '{"taragarmr":{"new":["<script>x</script> & y"],"existing":["a <b> & c"]}}' >"$WORK/warnings.json"
body servers '["taragarmr"]' WARNINGS="$WORK/warnings.json"
check 'warnings: html escaped' has '&lt;script&gt;x&lt;/script&gt; &amp; y'
check 'warnings: html escaped in details' has 'a &lt;b&gt; &amp; c'
check 'warnings: no raw tag' eval '! has "<script>"'

jq -n '{taragarmr:{new:[range(15)|"w\(.)"],existing:[range(12)|"e\(.)"]}}' >"$WORK/warnings.json"
body servers '["taragarmr"]' WARNINGS="$WORK/warnings.json"
check 'warnings: new capped at 10' has '- w9'
check 'warnings: new 11th dropped' eval '! has "- w10"'
check 'warnings: new more line' has '… and 5 more'
check 'warnings: existing more line' has '… and 2 more'

# --- warnings-diff.jq ----------------------------------------------------------
echo '{"warnings":{"a":["x /nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-source/f","same"],"b":["gone"],"c":[]}}' >"$WORK/wb.json"
printf "%s\n" '{"warnings":{"a":["x /nix/store/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb-source/f","same","new\n one"],"b":[],"c":[]}}' >"$WORK/wa.json"
diff_out="$(jq -cn -f "$SCRIPTS/lib/warnings-diff.jq" --argjson hosts '["a","b","c"]' \
    --slurpfile a "$WORK/wa.json" --slurpfile b "$WORK/wb.json" 2>/dev/null || true)"
check 'warnings-diff: new vs existing, store paths ignored, empty hosts dropped' \
    [ "$diff_out" = '{"a":{"new":["new one"],"existing":["x source/f","same"]}}' ]
echo '{"warnings":{"a":["  lead"]}}' >"$WORK/wb.json"
echo '{"warnings":{"a":["lead"]}}' >"$WORK/wa.json"
diff_out="$(jq -cn -f "$SCRIPTS/lib/warnings-diff.jq" --argjson hosts '["a"]' \
    --slurpfile a "$WORK/wa.json" --slurpfile b "$WORK/wb.json" 2>/dev/null || true)"
check 'warnings-diff: leading whitespace trimmed' [ "$diff_out" = '{"a":{"new":[],"existing":["lead"]}}' ]

# --- host-warnings.nix ---------------------------------------------------------
warns="$(nix eval --json --impure --expr "import $SCRIPTS/host-warnings.nix {
    a.config.warnings = [ \"w1\" ];
    b.config.warnings = [ ];
  } [ \"a\" \"b\" ]" 2>/dev/null || true)"
check 'host-warnings: warnings per host' [ "$warns" = '{"a":["w1"],"b":[]}' ]

# --- host-drvs.nix -------------------------------------------------------------
drvs="$(nix eval --json --impure --expr "import $SCRIPTS/host-drvs.nix {
    a.config.system.build.toplevel.drvPath = \"/a.drv\";
    b.config.system.build.toplevel.drvPath = \"/b.drv\";
    b-vm.config.system.build.toplevel.drvPath = \"/vm.drv\";
  } [ \"a\" \"b\" ]" 2>/dev/null || true)"
check 'host-drvs: only listed hosts' [ "$drvs" = '{"a":"/a.drv","b":"/b.drv"}' ]

[ "$failures" -eq 0 ] || { echo "$failures failure(s)"; exit 1; }
