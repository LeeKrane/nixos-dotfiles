#!/usr/bin/env bash
# Tests scripts/flake-update-notify.sh against file:// fixtures, with
# notify-send and xdg-open stubbed on PATH. Run:
#   nix shell nixpkgs#curl nixpkgs#jq nixpkgs#gawk --command bash scripts/tests/flake-update-notify-test.sh
set -euo pipefail

SCRIPT="$(dirname "$(readlink -f "$0")")/../flake-update-notify.sh"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/bin"
# notify-send stub: records its arguments NUL-separated (bodies span lines),
# prints $STUB_ACTION (the clicked action), exits $STUB_EXIT.
cat >"$WORK/bin/notify-send" <<'EOF'
#!/usr/bin/env bash
printf '%s\0' "$@" >"$LOG_DIR/notify"
printf '%s' "${STUB_ACTION:-}"
exit "${STUB_EXIT:-0}"
EOF
cat >"$WORK/bin/xdg-open" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$LOG_DIR/xdg"
EOF
# systemd-run stub: records its own arguments NUL-separated, then drops its
# leading flags and execs the wrapped command, so the xdg-open stub it
# launches still records as usual.
cat >"$WORK/bin/systemd-run" <<'EOF'
#!/usr/bin/env bash
printf '%s\0' "$@" >"$LOG_DIR/systemd-run"
while [[ "$1" == -* ]]; do shift; done
exec "$@"
EOF
chmod +x "$WORK/bin/notify-send" "$WORK/bin/xdg-open" "$WORK/bin/systemd-run"

STATE_FILE="$WORK/state/flake-update-notify/last-sha"
failures=0

# pr_json SHA TITLE BODY: one-element pulls array, written to $WORK/pulls.json.
pr_json() {
    jq -n --arg sha "$1" --arg t "$2" --arg b "$3" \
        '[{head: {sha: $sha}, html_url: "https://github.com/a/b/pull/3", title: $t, body: $b}]' \
        >"$WORK/pulls.json"
}

# run [ENV=VAL...]: runs the script with stubs; sets $status.
run() {
    rm -rf "$WORK/log"
    mkdir -p "$WORK/log"
    status=0
    env PATH="$WORK/bin:$PATH" LOG_DIR="$WORK/log" XDG_STATE_HOME="$WORK/state" \
        REPO=a/b BRANCH=ci/flake-update PULLS_URL="file://$WORK/pulls.json" \
        "$@" bash "$SCRIPT" >/dev/null 2>"$WORK/log/stderr" || status=$?
}

check() { # check NAME CONDITION...
    local name=$1
    shift
    if "$@"; then echo "ok   $name"; else echo "FAIL $name"; failures=$((failures + 1)); fi
}
notified() { [ -f "$WORK/log/notify" ]; }
notify_has() { # exact match against any single notify-send argument
    local arg
    while IFS= read -r -d '' arg; do [ "$arg" = "$1" ] && return 0; done <"$WORK/log/notify"
    return 1
}
systemd_run_has() { # exact match against any single systemd-run argument
    local arg
    while IFS= read -r -d '' arg; do [ "$arg" = "$1" ] && return 0; done <"$WORK/log/systemd-run"
    return 1
}
state_is() { [ "$(command cat "$STATE_FILE" 2>/dev/null)" = "$1" ]; }

# shellcheck disable=SC2016 # backticks in test fixture strings, don't expand here
VERSIONS_BODY=$(printf '%s\n' \
    'Gate: ✅ passed ([run](https://example.invalid))' \
    '' \
    '### Package versions' \
    '| Package | Before | After |' \
    '| --- | --- | --- |' \
    '| linux | 7.2.3 | 7.2.5 |' \
    '|  `claude-code`  | `2.1.280` | `2.1.289` |' \
    '| NVIDIA driver | - | 580.1 |' \
    '' \
    '### Inputs' \
    '| Input | From | To | Changes |' \
    '| --- | --- | --- | --- |' \
    '| nixpkgs | 2026-09-04 | 2026-10-03 | x |' \
    '' \
    'CI checks eval only.')
INPUTS_BODY=$(printf '%s\n' \
    '### Inputs' \
    '| Input | From | To | Changes |' \
    '| --- | --- | --- | --- |' \
    '| nixpkgs | 2026-09-04 | 2026-10-03 | x |' \
    '| disko | 2026-06-11 | 2026-09-18 | x |')

# versions body: first notification
rm -rf "$WORK/state"
pr_json sha1 'Update flake inputs' "$VERSIONS_BODY"
run
check 'versions body: exit 0' [ "$status" -eq 0 ]
check 'versions body: notified' notified
check 'versions body: summary' notify_has 'Flake update ready'
check 'versions body: normal urgency' notify_has 'normal'
check 'versions body: app name' notify_has 'Dotfiles'
check 'versions body: action' notify_has '--action=open=Open PR'
check 'versions body: sticky' notify_has '--expire-time=0'
check 'versions body: expanded hint' notify_has '--hint=boolean:x-ii-expanded:true'
check 'versions body: lines' notify_has $'linux 7.2.3 → 7.2.5\nclaude-code 2.1.280 → 2.1.289\nNVIDIA driver - → 580.1'
check 'versions body: state written' state_is sha1
check 'versions body: no xdg-open' [ ! -f "$WORK/log/xdg" ]

# dedupe: same SHA stays silent
run
check 'dedupe: exit 0' [ "$status" -eq 0 ]
check 'dedupe: not notified' eval '! notified'

# new SHA notifies again
pr_json sha2 'Update flake inputs' "$VERSIONS_BODY"
run
check 'new sha: notified' notified
check 'new sha: state updated' state_is sha2

# no pr clears state
printf '[]' >"$WORK/pulls.json"
run
check 'no pr clears state: exit 0' [ "$status" -eq 0 ]
check 'no pr clears state: not notified' eval '! notified'
check 'no pr clears state: state removed' [ ! -e "$STATE_FILE" ]

# gate failing title
pr_json sha3 '[gate failing] Update flake inputs' "$VERSIONS_BODY"
run
check 'gate failing: summary' notify_has 'Flake update ready (gate failing)'
check 'gate failing: critical' notify_has 'critical'

# inputs-only body
pr_json sha4 'Update flake inputs' "$INPUTS_BODY"
run
check 'inputs only: count' notify_has '2 inputs updated'

# neither table: title fallback
pr_json sha5 'Update flake inputs' 'free text'
run
check 'no tables: title' notify_has 'Update flake inputs'

# crlf body
pr_json sha6 'Update flake inputs' "$(printf '%s' "$VERSIONS_BODY" | sed 's/$/\r/')"
run
check 'crlf body: lines' notify_has $'linux 7.2.3 → 7.2.5\nclaude-code 2.1.280 → 2.1.289\nNVIDIA driver - → 580.1'

# click opens the PR, via a transient systemd-run unit so the browser
# xdg-open launches survives this oneshot unit's cgroup
pr_json sha7 'Update flake inputs' "$VERSIONS_BODY"
run STUB_ACTION=open
check 'click: systemd-run launches xdg-open' systemd_run_has 'xdg-open'
check 'click: xdg-open url' grep -qxF 'https://github.com/a/b/pull/3' "$WORK/log/xdg"

# curl failure: non-zero, no notification, state untouched
pr_json sha8 'Update flake inputs' "$VERSIONS_BODY"
run PULLS_URL="file://$WORK/missing.json"
check 'curl failure: non-zero' [ "$status" -ne 0 ]
check 'curl failure: not notified' eval '! notified'
check 'curl failure: state untouched' state_is sha7

# notify-send failure: non-zero, state removed so the next run retries
run STUB_EXIT=1
check 'notify-send failure: non-zero' [ "$status" -ne 0 ]
check 'notify-send failure: state removed' [ ! -e "$STATE_FILE" ]

# missing env
run REPO=
check 'missing REPO: non-zero' [ "$status" -ne 0 ]

echo
if [ "$failures" -eq 0 ]; then echo 'all passed'; else echo "$failures failed"; exit 1; fi
