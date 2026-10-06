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
# busctl stub: the notification-daemon probe. Never touches D-Bus; exits
# $STUB_BUSCTL_EXIT (0 unless overridden).
command cat >"$WORK/bin/busctl" <<'EOF'
#!/usr/bin/env bash
exit "${STUB_BUSCTL_EXIT:-0}"
EOF
chmod +x "$WORK/bin/notify-send" "$WORK/bin/xdg-open" "$WORK/bin/systemd-run" "$WORK/bin/busctl"

STATE_FILE="$WORK/state/flake-update-notify/last-seen"
failures=0

# pr_json SHA TITLE BODY [NUMBER=3]: one-element pulls array, written to
# $WORK/pulls.json.
pr_json() {
    local number="${4:-3}"
    jq -n --arg sha "$1" --arg t "$2" --arg b "$3" --argjson n "$number" \
        '[{head: {sha: $sha}, html_url: ("https://github.com/a/b/pull/" + ($n | tostring)), number: $n, title: $t, body: $b}]' \
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
state_is() { [ "$(sed -n '1p' "$STATE_FILE" 2>/dev/null)" = "$1" ]; }

# security_body SENTENCE: a ### Package versions table followed by a
# ### Security section with summary sentence $1 and a ### Local builds
# section after it, matching the real PR body assembled by
# .github/workflows/update.yml when the security job succeeds.
security_body() {
    printf '%s\n' \
        '### Package versions' \
        '| Package | Before | After |' \
        '| --- | --- | --- |' \
        '| linux | 7.2.3 | 7.2.5 |' \
        '' \
        '### Security' \
        '' \
        "$1" \
        '' \
        '### Local builds' \
        '' \
        'hosta: no new local builds (3 total)'
}

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
# 4-column form (scripts/update-summary.sh's version-diff.jq adds a Hosts
# column when a package's before/after differs across hosts): both rows of
# the same package, split by host group.
SPLIT_VERSIONS_BODY=$(printf '%s\n' \
    '### Package versions' \
    '| Package | Before | After | Hosts |' \
    '| --- | --- | --- | --- |' \
    '| NVIDIA driver | 610 | 615 | tariognatha |' \
    '| NVIDIA driver | 610 | 620 | tarmantria |' \
    '')
# more than 5 package rows: the notification body caps at the first 5, with a
# one-line count of the rest
MANY_VERSIONS_BODY=$(
    {
        printf '%s\n' '### Package versions' '| Package | Before | After |' '| --- | --- | --- |'
        for i in $(seq 1 7); do printf '| pkg%d | 1 | 2 |\n' "$i"; done
        echo
    }
)
# exactly 5 package rows: no truncation note
EXACT5_VERSIONS_BODY=$(
    {
        printf '%s\n' '### Package versions' '| Package | Before | After |' '| --- | --- | --- |'
        for i in $(seq 1 5); do printf '| pkg%d | 1 | 2 |\n' "$i"; done
        echo
    }
)
# a package split across hosts (the 4-column Hosts form) straddling the cap
# boundary: pkg5's two rows count as one package, so the cap lands after
# both of them, and pkg6 is the only one dropped. Every row carries a Hosts
# cell, split or not: update-summary.sh's version-diff.jq renders the whole
# table in the 4-column form as soon as any one package needs it, not just
# that package's own rows.
SPLIT_CAP_VERSIONS_BODY=$(printf '%s\n' \
    '### Package versions' \
    '| Package | Before | After | Hosts |' \
    '| --- | --- | --- | --- |' \
    '| pkg1 | 1 | 2 | hosta, hostb |' \
    '| pkg2 | 1 | 2 | hosta, hostb |' \
    '| pkg3 | 1 | 2 | hosta, hostb |' \
    '| pkg4 | 1 | 2 | hosta, hostb |' \
    '| pkg5 | 1 | 2 | hosta |' \
    '| pkg5 | 1 | 3 | hostb |' \
    '| pkg6 | 1 | 2 | hosta, hostb |' \
    '')
# the security job itself failed (.github/workflows/update.yml): no
# ### Security heading, just a headingless "Security scan failed" line with
# a run link.
SECURITY_SCAN_FAILED_BODY=$(printf '%s\n' \
    '### Package versions' \
    '| Package | Before | After |' \
    '| --- | --- | --- |' \
    '| linux | 7.2.3 | 7.2.5 |' \
    '' \
    'Security scan failed ([run](https://example.invalid/actions/runs/1))')

# versions body: first notification
rm -rf "$WORK/state"
pr_json sha1 'Update flake inputs' "$VERSIONS_BODY"
run
check 'versions body: exit 0' [ "$status" -eq 0 ]
check 'versions body: notified' notified
check 'versions body: summary' notify_has 'Flake update ready (#3)'
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

# same SHA, same PR number, body changed notifies again
pr_json sha1 'Update flake inputs' "$INPUTS_BODY"
run
check 'body changed: notified' notified
check 'body changed: state sha unchanged' state_is sha1

# new SHA notifies again
pr_json sha2 'Update flake inputs' "$VERSIONS_BODY"
run
check 'new sha: notified' notified
check 'new sha: state updated' state_is sha2

# same SHA and body, different PR number (the previous update PR was merged
# or closed by hand, so the pr job opened a new one reusing the same commit
# and body) notifies again
pr_json sha2 'Update flake inputs' "$VERSIONS_BODY" 4
run
check 'new pr number: notified' notified
check 'new pr number: state unchanged sha' state_is sha2

# no pr clears state
printf '[]' >"$WORK/pulls.json"
run
check 'no pr clears state: exit 0' [ "$status" -eq 0 ]
check 'no pr clears state: not notified' eval '! notified'
check 'no pr clears state: state removed' [ ! -e "$STATE_FILE" ]

# gate failing title
pr_json sha3 '[gate failing] Update flake inputs' "$VERSIONS_BODY"
run
check 'gate failing: summary' notify_has 'Flake update ready (#3) (gate failing)'
check 'gate failing: critical' notify_has 'critical'

# PR number in the summary, both normal and gate failing
pr_json sha3b 'Update flake inputs' "$VERSIONS_BODY" 42
run
check 'pr number: summary' notify_has 'Flake update ready (#42)'
pr_json sha3c '[gate failing] Update flake inputs' "$VERSIONS_BODY" 43
run
check 'pr number gate failing: summary' notify_has 'Flake update ready (#43) (gate failing)'

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

# 4-column package versions table: each row's Hosts column is appended in
# parentheses
pr_json sha8 'Update flake inputs' "$SPLIT_VERSIONS_BODY"
run
check '4-column: notified' notified
check '4-column: lines' notify_has $'NVIDIA driver 610 → 615 (tariognatha)\nNVIDIA driver 610 → 620 (tarmantria)'

# more than 5 package rows: capped at 5 plus a "...and N more" line
pr_json sha10 'Update flake inputs' "$MANY_VERSIONS_BODY"
run
check 'top-5 truncation: lines' notify_has $'pkg1 1 → 2\npkg2 1 → 2\npkg3 1 → 2\npkg4 1 → 2\npkg5 1 → 2\n...and 2 more'

# exactly 5 package rows: no overflow line
pr_json sha11 'Update flake inputs' "$EXACT5_VERSIONS_BODY"
run
check 'exactly 5: no overflow line' notify_has $'pkg1 1 → 2\npkg2 1 → 2\npkg3 1 → 2\npkg4 1 → 2\npkg5 1 → 2'

# split package straddling the cap boundary: both its rows count as one
# package, so the cap lands after them and only pkg6 is dropped
pr_json sha12 'Update flake inputs' "$SPLIT_CAP_VERSIONS_BODY"
run
check 'split cap: lines' notify_has $'pkg1 1 → 2 (hosta, hostb)\npkg2 1 → 2 (hosta, hostb)\npkg3 1 → 2 (hosta, hostb)\npkg4 1 → 2 (hosta, hostb)\npkg5 1 → 2 (hosta)\npkg5 1 → 3 (hostb)\n...and 1 more'

# Security section: "No CVE changes" sentence appended verbatim as the last line
pr_json sha13 'Update flake inputs' "$(security_body 'No CVE changes')"
run
check 'security no cve: lines' notify_has $'linux 7.2.3 → 7.2.5\nNo CVE changes'

# Security section: "N fixed, M new" sentence. New CVEs must not affect
# urgency -- only the [gate failing] title does.
pr_json sha14 'Update flake inputs' "$(security_body '3 CVEs fixed, 2 new')"
run
check 'security fixed and new: lines' notify_has $'linux 7.2.3 → 7.2.5\n3 CVEs fixed, 2 new'
check 'security fixed and new: urgency stays normal' notify_has 'normal'
check 'security fixed and new: not critical' eval '! notify_has critical'

# Security section: "N fixed" sentence only
pr_json sha15 'Update flake inputs' "$(security_body '1 CVE fixed')"
run
check 'security fixed only: lines' notify_has $'linux 7.2.3 → 7.2.5\n1 CVE fixed'

# Security section: "M new" sentence only. Same urgency regression as above.
pr_json sha16 'Update flake inputs' "$(security_body '2 new CVEs')"
run
check 'security new only: lines' notify_has $'linux 7.2.3 → 7.2.5\n2 new CVEs'
check 'security new only: urgency stays normal' notify_has 'normal'
check 'security new only: not critical' eval '! notify_has critical'

# Security job itself failed: no ### Security heading, just a headingless
# "Security scan failed" line, its "([run](...))" link stripped to plain text
pr_json sha17 'Update flake inputs' "$SECURITY_SCAN_FAILED_BODY"
run
check 'security scan failed: lines' notify_has $'linux 7.2.3 → 7.2.5\nSecurity scan failed'

# curl failure: non-zero, no notification, state untouched
pr_json sha9 'Update flake inputs' "$VERSIONS_BODY"
run PULLS_URL="file://$WORK/missing.json"
check 'curl failure: non-zero' [ "$status" -ne 0 ]
check 'curl failure: not notified' eval '! notified'
check 'curl failure: state untouched' state_is sha17

# notification daemon probe fails: non-zero, no notification, state
# untouched -- same retryable path as a curl failure, so a daemon that
# isn't up yet never gets a popup shown before the retry succeeds
run STUB_BUSCTL_EXIT=1
check 'probe failure: non-zero' [ "$status" -ne 0 ]
check 'probe failure: not notified' eval '! notified'
check 'probe failure: state untouched' state_is sha17
check 'probe failure: stderr warning' grep -qF 'notification daemon not reachable' "$WORK/log/stderr"

# notify-send fails immediately after a passing probe: --wait would block
# far longer than this for a real notification, so a quick failure means no
# popup was ever shown -- exit 1, state removed, so it's retried like the
# probe above, and a warning goes to stderr.
run STUB_EXIT=1
check 'notify-send fails fast: exit 1' [ "$status" -eq 1 ]
check 'notify-send fails fast: state removed' [ ! -e "$STATE_FILE" ]
check 'notify-send fails fast: stderr warning' grep -qF 'notify-send failed quickly' "$WORK/log/stderr"

# notify-send fails after a delay: a popup was likely shown already, so a
# retry must not repeat it -- exit 0, state kept, warning on stderr.
# NOTIFY_FAIL_THRESHOLD=0 stands in for an actual delay: elapsed seconds is
# never less than a 0-second threshold, so this exercises the "past the
# threshold" branch without the test having to sleep past the real
# default.
pr_json sha9b 'Update flake inputs' "$VERSIONS_BODY"
run STUB_EXIT=1 NOTIFY_FAIL_THRESHOLD=0
check 'notify-send fails slow: exit 0' [ "$status" -eq 0 ]
check 'notify-send fails slow: state kept' state_is sha9b
check 'notify-send fails slow: stderr warning' grep -qF 'notify-send failed after a delay' "$WORK/log/stderr"

# missing env
run REPO=
check 'missing REPO: non-zero' [ "$status" -ne 0 ]

echo
if [ "$failures" -eq 0 ]; then echo 'all passed'; else echo "$failures failed"; exit 1; fi
