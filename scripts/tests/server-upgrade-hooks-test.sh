#!/usr/bin/env bash
# Tests scripts/server-upgrade-hooks.sh with git, nix-env, systemctl, journalctl, curl and the
# report command stubbed on PATH, and the system directories replaced by symlinks under a temp
# dir. Run:
#   nix shell nixpkgs#jq nixpkgs#gawk --command bash scripts/tests/server-upgrade-hooks-test.sh
set -euo pipefail

SCRIPT="$(dirname "$(readlink -f "$0")")/../server-upgrade-hooks.sh"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

STATE="$WORK/state"
LOG="$WORK/log"
mkdir -p "$WORK/bin"

# git stub: `ls-remote` prints "$STUB_SHA<TAB>refs/heads/deploy", or fails with $STUB_GIT_FAIL.
command cat >"$WORK/bin/git" <<'EOF'
#!/usr/bin/env bash
[ -z "${STUB_GIT_FAIL:-}" ] || exit 128
[ -z "${STUB_SHA:-}" ] || printf '%s\trefs/heads/deploy\n' "$STUB_SHA"
EOF
# systemctl stub: records every call; --failed lists $STUB_FAILED_UNITS (space separated).
command cat >"$WORK/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$LOG_DIR/systemctl"
if [ "$1" = --failed ]; then
    for u in ${STUB_FAILED_UNITS:-}; do printf '%s loaded failed failed x\n' "$u"; done
fi
exit 0
EOF
command cat >"$WORK/bin/nix-env" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$LOG_DIR/nix-env"
EOF
command cat >"$WORK/bin/journalctl" <<'EOF'
#!/usr/bin/env bash
echo "journal line"
EOF
# curl stub (ntfy): records the url and body, fails with $STUB_CURL_EXIT.
command cat >"$WORK/bin/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$LOG_DIR/curl"
exit "${STUB_CURL_EXIT:-0}"
EOF
command cat >"$WORK/bin/server-upgrade-report" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$LOG_DIR/report"
exit "${STUB_REPORT_EXIT:-0}"
EOF
command cat >"$WORK/health" <<'EOF'
#!/usr/bin/env bash
exit "${STUB_HEALTH_EXIT:-0}"
EOF
chmod +x "$WORK"/bin/* "$WORK/health"

failures=0
check() { # check NAME CONDITION...
    local name=$1
    shift
    if "$@"; then echo "ok   $name"; else echo "FAIL $name"; failures=$((failures + 1)); fi
}

# mksystem NAME REVISION KERNEL: a fake system closure with its nixos-version, kernel link and
# switch-to-configuration (which records its argument).
mksystem() {
    local d="$WORK/store/$1"
    mkdir -p "$d/sw/bin" "$d/bin"
    printf '#!/usr/bin/env bash\necho %s\n' "$2" >"$d/sw/bin/nixos-version"
    # shellcheck disable=SC2016 # $LOG_DIR and $* belong to the generated script
    printf '#!/usr/bin/env bash\necho "%s $*" >>"$LOG_DIR/switch"\n' "$1" >"$d/bin/switch-to-configuration"
    chmod +x "$d/sw/bin/nixos-version" "$d/bin/switch-to-configuration"
    ln -sfn "$WORK/store/kernel-$3" "$d/kernel"
    ln -sfn "$WORK/store/kernel-$3" "$d/initrd"
    ln -sfn "$WORK/store/kernel-$3" "$d/kernel-modules"
}
point() { ln -sfn "$WORK/store/$2" "$WORK/$1"; } # point LINK SYSTEM

# fresh: old system "old" (revision OLDREV, kernel k1) running, booted and in the profile.
fresh() {
    rm -rf "$STATE" "$LOG" "$WORK/store"
    mkdir -p "$STATE" "$LOG" "$WORK/store"
    mksystem old OLDREV k1
    mksystem newsame NEWREV k1
    mksystem newkern NEWREV k2
    point current old
    point booted old
    point profile old
    unset STUB_SHA STUB_GIT_FAIL STUB_FAILED_UNITS STUB_CURL_EXIT STUB_REPORT_EXIT STUB_HEALTH_EXIT || true
}
run() { # run SUBCOMMAND [ENV=VAL...]: sets $status
    local sub=$1
    shift
    status=0
    env PATH="$WORK/bin:$PATH" LOG_DIR="$LOG" HOST_NAME=tarronax STATE_DIR="$STATE" \
        CURRENT_SYSTEM="$WORK/current" BOOTED_SYSTEM="$WORK/booted" SYSTEM_PROFILE="$WORK/profile" \
        HEALTH_CHECK="$WORK/health" BOOT_SETTLE_TIMEOUT=5 REPORT_CMD="$WORK/bin/server-upgrade-report" \
        "$@" bash "$SCRIPT" "$sub" >"$LOG/stdout" 2>"$LOG/stderr" || status=$?
}
logged() { grep -qF -- "$2" "$LOG/$1" 2>/dev/null; } # logged FILE TEXT
state_is() { [ "$(command cat "$STATE/$1" 2>/dev/null)" = "$2" ]; }
outbox_count() { find "$STATE/outbox" -name '*.json' 2>/dev/null | wc -l; }
only_message() { jq -r "$1" "$STATE"/outbox/*.json; }

# --- condition -----------------------------------------------------------------------------
fresh
run condition STUB_SHA=NEWREV
check 'condition: new sha runs' [ "$status" -eq 0 ]
check 'condition: target sha recorded' state_is target-sha NEWREV

fresh
printf 'NEWREV\n' >"$STATE/failed-sha"
run condition STUB_SHA=NEWREV
check 'condition: a failed sha is skipped' [ "$status" -eq 1 ]

fresh
printf 'NEWREV\n' >"$STATE/failed-sha"
run condition STUB_SHA=NEWER
check 'condition: a newer sha than the failed one runs' [ "$status" -eq 0 ]

fresh
run condition STUB_SHA=OLDREV
check 'condition: already deployed, no reboot pending: skipped' [ "$status" -eq 1 ]

fresh
point current newsame
run condition STUB_SHA=NEWREV
check 'condition: deployed with the booted kernel: skipped' [ "$status" -eq 1 ]
point current newkern
point booted old
run condition STUB_SHA=NEWREV
check 'condition: deployed with a reboot pending: runs' [ "$status" -eq 0 ]

fresh
run condition STUB_GIT_FAIL=1
check 'condition: ls-remote failure skips the run' [ "$status" -eq 1 ]
run condition
check 'condition: missing deploy branch skips the run' [ "$status" -eq 1 ]

# --- pre / post ----------------------------------------------------------------------------
fresh
run pre STUB_FAILED_UNITS="old.service"
check 'pre: records the running system' state_is pre-switch "$(readlink -f "$WORK/store/old")"
check 'pre: records the profile' state_is pre-profile "$(readlink -f "$WORK/store/old")"
check 'pre: records already failed units' state_is failed-before old.service

fresh
printf 'NEWREV\n' >"$STATE/target-sha"
run pre
point current newsame
point profile newsame
run post
check 'post: healthy switch succeeds' [ "$status" -eq 0 ]
check 'post: no pending check' [ ! -e "$STATE/pending-check" ]

fresh
printf 'NEWREV\n' >"$STATE/target-sha"
run pre
point profile newkern
run post
check 'post: new kernel not active yet defers the check' [ "$status" -eq 0 ]
check 'post: pending check names the sha' state_is pending-check NEWREV

fresh
printf 'NEWREV\n' >"$STATE/target-sha"
run pre STUB_FAILED_UNITS="old.service"
point current newsame
point profile newsame
run post STUB_FAILED_UNITS="old.service"
check 'post: a unit that was already failing does not fail the upgrade' [ "$status" -eq 0 ]
run post STUB_FAILED_UNITS="old.service new.service"
check 'post: a newly failed unit fails the upgrade' [ "$status" -ne 0 ]
check 'post: failure is staged as health' state_is stage health
run post STUB_HEALTH_EXIT=1
check 'post: the host health check failing fails the upgrade' [ "$status" -ne 0 ]

fresh
printf 'NEWREV\n' >"$STATE/target-sha"
printf 'BADREV\n' >"$STATE/failed-sha"
run pre
point current newsame
point profile newsame
run post
check 'post: recovery queues one message' [ "$(outbox_count)" -eq 1 ]
check 'post: recovery message kind' [ "$(only_message .kind)" = recovered ]
check 'post: recovery title' [ "$(only_message .title)" = 'tarronax recovered on NEWREV' ]
check 'post: failed sha cleared' [ ! -e "$STATE/failed-sha" ]

# --- failed --------------------------------------------------------------------------------
fresh
printf 'NEWREV\n' >"$STATE/target-sha"
run pre
run failed
check 'failed: a build failure changes nothing, no rollback' eval '! logged nix-env --set'
check 'failed: stage is build' [ "$(only_message .stage)" = build ]
check 'failed: not rolled back' [ "$(only_message .rolled_back)" = no ]
check 'failed: sha marked failed' state_is failed-sha NEWREV
check 'failed: high priority' [ "$(only_message .priority)" = high ]
check 'failed: title' [ "$(only_message .title)" = 'tarronax upgrade failed (NEWREV)' ]
check 'failed: journal in the body' [ "$(only_message .body | grep -c 'journal line')" -eq 1 ]

fresh
printf 'NEWREV\n' >"$STATE/target-sha"
run pre
point current newsame
point profile newsame
run failed
check 'failed: a changed system is rolled back to the previous one' logged nix-env "--set $(readlink -f "$WORK/store/old")"
check 'failed: via its own switch-to-configuration' logged switch 'old switch'
check 'failed: stage is activation' [ "$(only_message .stage)" = activation ]
check 'failed: rolled back' [ "$(only_message .rolled_back)" = yes ]

fresh
printf 'NEWREV\n' >"$STATE/target-sha"
run pre
point current newsame
point profile newsame
printf 'health\n' >"$STATE/stage"
run failed
check 'failed: a health failure keeps its stage' [ "$(only_message .stage)" = health ]

fresh
printf 'NEWREV\n' >"$STATE/target-sha"
run pre
point profile newkern
printf 'NEWREV\n' >"$STATE/pending-check"
run failed
check 'failed: a moved profile alone is rolled back too' logged nix-env '--set'
check 'failed: a rollback drops the pending check' [ ! -e "$STATE/pending-check" ]

# --- boot-health ---------------------------------------------------------------------------
fresh
run boot-health
check 'boot-health: nothing pending, nothing done' [ "$status" -eq 0 ]
check 'boot-health: no reboot without a pending check' eval '! logged systemctl reboot'

fresh
printf 'NEWREV\n' >"$STATE/pending-check"
run pre
run boot-health
check 'boot-health: healthy clears the pending check' [ ! -e "$STATE/pending-check" ]
check 'boot-health: healthy, no message without an earlier failure' [ "$(outbox_count)" -eq 0 ]

fresh
printf 'NEWREV\n' >"$STATE/pending-check"
printf 'BADREV\n' >"$STATE/failed-sha"
run pre
run boot-health
check 'boot-health: recovery message after an earlier failure' [ "$(only_message .kind)" = recovered ]

fresh
printf 'NEWREV\n' >"$STATE/pending-check"
run pre
run boot-health STUB_HEALTH_EXIT=1
check 'boot-health: unhealthy rolls back for the next boot' logged switch 'old boot'
check 'boot-health: unhealthy reboots' logged systemctl reboot
check 'boot-health: marks the sha failed' state_is failed-sha NEWREV
check 'boot-health: remembers the rollback' [ -e "$STATE/rolled-back" ]
check 'boot-health: stage' [ "$(only_message .stage)" = boot-health ]
check 'boot-health: keeps the pending check for the rolled-back boot' [ -e "$STATE/pending-check" ]
# second boot, rolled-back system still unhealthy: no further reboot
rm -f "$LOG/systemctl" "$STATE/outbox"/*.json
run boot-health STUB_HEALTH_EXIT=1
check 'boot-health: a second failure does not reboot again' eval '! logged systemctl reboot'
check 'boot-health: a second failure says the rollback did not help' [ "$(only_message .rolled_back)" = 'no, the rollback did not help' ]
check 'boot-health: second failure clears its markers' [ ! -e "$STATE/rolled-back" ]

fresh
printf 'NEWREV\n' >"$STATE/pending-check"
printf 'NEWREV\n' >"$STATE/failed-sha"
: >"$STATE/rolled-back"
run pre
run boot-health
check 'boot-health: a healthy rolled-back system queues no recovery' [ "$(outbox_count)" -eq 0 ]
check 'boot-health: and clears the markers' [ ! -e "$STATE/pending-check" ]

# --- deliver -------------------------------------------------------------------------------
fresh
printf 'NEWREV\n' >"$STATE/target-sha"
run pre
run failed
printf 'token' >"$WORK/ntfy-token"
printf 'token' >"$WORK/github-token"
DELIVER=(NTFY_URL=http://ntfy.test NTFY_TOKEN_FILE="$WORK/ntfy-token" GITHUB_TOKEN_FILE="$WORK/github-token")
run deliver STUB_CURL_EXIT=22 "${DELIVER[@]}"
check 'deliver: ntfy down keeps the message' [ "$(outbox_count)" -eq 1 ]
check 'deliver: ntfy down exits non-zero for the retry' [ "$status" -ne 0 ]
check 'deliver: github still received it' logged report 'failed tarronax NEWREV build no'
rm -f "$LOG/report" "$LOG/curl"
run deliver STUB_CURL_EXIT=22 "${DELIVER[@]}"
check 'deliver: a channel that already took it is not asked again' eval '! logged report tarronax'
rm -f "$LOG/curl"
run deliver "${DELIVER[@]}"
check 'deliver: both channels accepted: exit 0' [ "$status" -eq 0 ]
check 'deliver: both channels accepted: message removed' [ "$(outbox_count)" -eq 0 ]
check 'deliver: ntfy topic' logged curl 'http://ntfy.test/server-upgrades'
check 'deliver: ntfy title' logged curl 'Title: tarronax upgrade failed (NEWREV)'
check 'deliver: ntfy priority' logged curl 'Priority: high'

# GitHub down: the message stays until the report command succeeds
fresh
printf 'NEWREV\n' >"$STATE/target-sha"
run pre
run failed
run deliver STUB_REPORT_EXIT=1 "${DELIVER[@]}"
check 'deliver: github down keeps the message' [ "$(outbox_count)" -eq 1 ]
run deliver "${DELIVER[@]}"
check 'deliver: github back: message removed' [ "$(outbox_count)" -eq 0 ]

# the report command exits 22 (5xx) or 44 (404/422) too, not just 1: still queued, not lost
fresh
printf 'NEWREV\n' >"$STATE/target-sha"
run pre
run failed
run deliver STUB_REPORT_EXIT=44 "${DELIVER[@]}"
check 'deliver: report exit 44 keeps the message' [ "$(outbox_count)" -eq 1 ]
check 'deliver: report exit 44 exits non-zero' [ "$status" -ne 0 ]
run deliver STUB_REPORT_EXIT=22 "${DELIVER[@]}"
check 'deliver: report exit 22 keeps the message' [ "$(outbox_count)" -eq 1 ]

# a host without tokens treats both channels as done
fresh
printf 'NEWREV\n' >"$STATE/target-sha"
run pre
run failed
run deliver
check 'deliver: unconfigured channels do not hold messages back' [ "$(outbox_count)" -eq 0 ]

echo
if [ "$failures" -eq 0 ]; then echo 'all passed'; else echo "$failures failed"; exit 1; fi
