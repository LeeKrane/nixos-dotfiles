#!/usr/bin/env bash
# Hooks of the automatic server upgrade (modules/nixos/server/auto-upgrade.nix), one subcommand
# per systemd hook. State lives in $STATE_DIR (/var/lib/server-upgrade):
#   target-sha     deploy SHA the current run builds (written by `condition`)
#   pre-switch     /run/current-system before the run, what a rollback restores
#   pre-profile    the system profile before the run
#   failed-before  units already failed before the run, so only new failures count
#   stage          "health" once the post-switch health check failed
#   pending-check  SHA of a generation built but not yet activated (waits for the reboot window)
#   failed-sha     last SHA that failed here; `condition` never retries it
#   rolled-back    set before a boot-health rollback reboot, so that reboots at most once
#   outbox/        queued messages, one JSON file each, removed once ntfy and GitHub took them
#
#   condition    nixos-upgrade ExecCondition: exit 0 to upgrade, 1 to skip the run
#   pre          ExecStartPre: record the state a rollback restores
#   post         ExecStartPost: health check the freshly activated system
#   failed       OnFailure: roll back if anything changed, mark the SHA failed, queue a message
#   boot-health  health check a generation that came up after an upgrade reboot
#   deliver      send the queued messages to ntfy and GitHub (exit 1 while any is undelivered)
#
# Environment (tests override the paths; the module sets the rest):
#   HOST_NAME           this host                                          required
#   HEALTH_CHECK        executable that exits 0 when the host is healthy   optional
#   NTFY_URL            e.g. http://192.168.82.1:2586; with NTFY_TOKEN_FILE  optional
#   GITHUB_TOKEN_FILE   enables the GitHub channel (read by the report command) optional
set -euo pipefail

: "${HOST_NAME:?HOST_NAME must be set}"
STATE_DIR="${STATE_DIR:-/var/lib/server-upgrade}"
REMOTE_URL="${REMOTE_URL:-https://github.com/LeeKrane/nixos-dotfiles}"
CURRENT_SYSTEM="${CURRENT_SYSTEM:-/run/current-system}"
BOOTED_SYSTEM="${BOOTED_SYSTEM:-/run/booted-system}"
SYSTEM_PROFILE="${SYSTEM_PROFILE:-/nix/var/nix/profiles/system}"
HEALTH_CHECK="${HEALTH_CHECK:-}"
NTFY_URL="${NTFY_URL:-}"
NTFY_TOPIC="${NTFY_TOPIC:-server-upgrades}"
NTFY_TOKEN_FILE="${NTFY_TOKEN_FILE:-}"
GITHUB_TOKEN_FILE="${GITHUB_TOKEN_FILE:-}"
REPORT_CMD="${REPORT_CMD:-server-upgrade-report}"
BOOT_SETTLE_TIMEOUT="${BOOT_SETTLE_TIMEOUT:-300}"
OUTBOX="$STATE_DIR/outbox"
export GITHUB_TOKEN_FILE

read_state() { command cat "$STATE_DIR/$1" 2>/dev/null || true; }
resolved() { readlink -f "$1"; }
failed_units() { systemctl --failed --plain --no-legend | awk '{ print $1 }' | sort; }

# The SHA the deploy branch points at, empty if the branch does not exist.
deploy_sha() { git ls-remote "$REMOTE_URL" refs/heads/deploy | awk 'NR == 1 { print $1 }'; }

# True when the booted kernel, initrd or kernel modules differ from the running system's.
reboot_pending() {
    local f
    for f in initrd kernel kernel-modules; do
        [ "$(readlink "$BOOTED_SYSTEM/$f")" = "$(readlink "$CURRENT_SYSTEM/$f")" ] || return 0
    done
    return 1
}

# Healthy: no unit failed since the run started (a unit that was already failing before it
# does not block upgrades), and the host's own HEALTH_CHECK passes.
health() {
    local now new
    # Fail closed: a failing `systemctl --failed` is a health failure, not an empty list.
    now="$(failed_units)" || {
        echo "health check failed, could not list the failed units" >&2
        return 1
    }
    new="$(comm -13 <(read_state failed-before) <(printf '%s\n' "$now"))"
    if [ -n "$new" ]; then
        echo "health check failed, units failed since the upgrade started:" >&2
        echo "$new" >&2
        return 1
    fi
    if [ -n "$HEALTH_CHECK" ]; then "$HEALTH_CHECK"; fi
}

# Puts the previous running system back as the system profile and runs its own
# switch-to-configuration ($1: switch, or boot when a reboot follows). Not
# `nixos-rebuild --rollback`: the previous profile generation can be one that was built but
# never booted.
rollback() {
    local pre
    pre="$(read_state pre-switch)"
    [ -n "$pre" ] || return 1
    # Callers run this as an `if` condition, where set -e is off: every step must fail it itself.
    nix-env -p "$SYSTEM_PROFILE" --set "$pre" || return 1
    "$pre/bin/switch-to-configuration" "$1" || return 1
}

# queue KIND SHA STAGE ROLLED_BACK: one outbox message (KIND: failed or recovered), then a
# best-effort kick of the delivery unit.
queue() {
    local kind="$1" sha="$2" stage="$3" rolled="$4" sha7 title priority body tmp
    sha7="${sha:0:7}"
    if [ "$kind" = failed ]; then
        title="$HOST_NAME upgrade failed ($sha7)"
        priority=high
        # No -b: after a boot-health rollback the upgrade's own log is in the previous boot.
        body="$(printf 'Stage: %s\nRolled back: %s\n\n' "$stage" "$rolled"
            journalctl -u nixos-upgrade -u server-upgrade-health -n 30 --no-pager 2>/dev/null || true)"
    else
        title="$HOST_NAME recovered on $sha7"
        priority=low
        body="Healthy again on $sha7."
    fi
    mkdir -p "$OUTBOX"
    tmp="$(mktemp -p "$OUTBOX" .tmp.XXXXXX)"
    jq -nc --arg kind "$kind" --arg host "$HOST_NAME" --arg sha "$sha" --arg stage "$stage" \
        --arg rolled "$rolled" --arg title "$title" --arg priority "$priority" --arg body "$body" \
        '{kind: $kind, host: $host, sha: $sha, stage: $stage, rolled_back: $rolled,
          title: $title, priority: $priority, body: $body, ntfy_done: false, github_done: false}' \
        >"$tmp" || { rm -f "$tmp"; return 1; }
    mv "$tmp" "$OUTBOX/$(date +%s%N)-$kind.json"
    systemctl start --no-block server-upgrade-notify.service || true
}

# A healthy run on SHA: tell the owner if this host had failed on an earlier SHA.
recover() {
    local failed
    failed="$(read_state failed-sha)"
    if [ -n "$failed" ] && [ "$failed" != "$1" ]; then
        rm -f "$STATE_DIR/failed-sha"
        queue recovered "$1" - -
    fi
}

cmd_condition() {
    local sha failed deployed
    sha="$(deploy_sha)" || exit 1
    [ -n "$sha" ] || exit 1
    failed="$(read_state failed-sha)"
    if [ "$sha" = "$failed" ]; then
        echo "$sha already failed on this host, skipping"
        exit 1
    fi
    deployed="$("$CURRENT_SYSTEM/sw/bin/nixos-version" --configuration-revision 2>/dev/null || true)"
    if [ "$sha" = "$deployed" ] && ! reboot_pending; then
        echo "already on $sha, nothing to do"
        exit 1
    fi
    # Never overlap the boot-time health check of a generation that is still being judged: `pre`
    # would overwrite the state its rollback needs and two switches could run at once.
    # (is-active is also true while "activating".) A leftover pending-check must not skip: it would
    # block every later run forever.
    if systemctl is-active --quiet server-upgrade-health; then
        echo "a boot health check is running, skipping"
        exit 1
    fi
    mkdir -p "$STATE_DIR"
    printf '%s\n' "$sha" >"$STATE_DIR/target-sha"
}

cmd_pre() {
    # First: if anything below fails, `failed` must not roll back to a stale earlier run's state.
    rm -f "$STATE_DIR/pre-switch" "$STATE_DIR/pre-profile"
    mkdir -p "$OUTBOX"
    resolved "$CURRENT_SYSTEM" >"$STATE_DIR/pre-switch"
    resolved "$SYSTEM_PROFILE" >"$STATE_DIR/pre-profile"
    failed_units >"$STATE_DIR/failed-before"
    rm -f "$STATE_DIR/stage"
}

cmd_post() {
    local sha
    sha="$(read_state target-sha)"
    # allowReboot: a new kernel is only built into the boot profile, then the host reboots
    # inside its window (or waits for it). Nothing is running yet, so boot-health checks it.
    if [ "$(resolved "$CURRENT_SYSTEM")" != "$(resolved "$SYSTEM_PROFILE")" ]; then
        printf '%s\n' "$sha" >"$STATE_DIR/pending-check"
        echo "new generation not active yet, its health check runs after the reboot"
        return 0
    fi
    if ! health; then
        echo health >"$STATE_DIR/stage"
        return 1
    fi
    rm -f "$STATE_DIR/pending-check"
    recover "$sha"
}

cmd_failed() {
    local sha stage rolled=no
    sha="$(read_state target-sha)"
    sha="${sha:-unknown}"
    stage="$(read_state stage)"
    if [ -z "$stage" ]; then
        if [ "$(resolved "$SYSTEM_PROFILE")" = "$(read_state pre-profile)" ]; then
            stage=build
        else
            stage=activation
        fi
    fi
    # Only a run that moved the profile or the running system needs undoing; a build failure
    # changed nothing.
    if [ -f "$STATE_DIR/pre-switch" ] \
        && { [ "$(resolved "$CURRENT_SYSTEM")" != "$(read_state pre-switch)" ] \
            || [ "$(resolved "$SYSTEM_PROFILE")" != "$(read_state pre-profile)" ]; }; then
        if rollback switch; then
            rolled=yes
            rm -f "$STATE_DIR/pending-check"
        else
            rolled="no, the rollback failed"
        fi
    fi
    printf '%s\n' "$sha" >"$STATE_DIR/failed-sha"
    queue failed "$sha" "$stage" "$rolled"
}

cmd_boot_health() {
    local sha
    [ -f "$STATE_DIR/pending-check" ] || return 0
    sha="$(read_state pending-check)"
    # Let the system settle; a degraded or timed-out answer is judged by health below.
    timeout "$BOOT_SETTLE_TIMEOUT" systemctl is-system-running --wait >/dev/null 2>&1 || true
    if health; then
        rm -f "$STATE_DIR/pending-check" "$STATE_DIR/rolled-back"
        recover "$sha"
        return 0
    fi
    if [ -f "$STATE_DIR/rolled-back" ]; then
        # Already rolled back once and still unhealthy: another reboot would not help.
        rm -f "$STATE_DIR/pending-check" "$STATE_DIR/rolled-back"
        queue failed "$sha" boot-health "no, the rollback did not help"
        return 0
    fi
    printf '%s\n' "$sha" >"$STATE_DIR/failed-sha"
    : >"$STATE_DIR/rolled-back"
    if rollback boot; then
        queue failed "$sha" boot-health yes
        systemctl reboot
    else
        queue failed "$sha" boot-health "no, the rollback failed"
    fi
}

mark_done() { # FILE KEY
    jq --arg k "$2" '.[$k] = true' "$1" >"$1.tmp" && mv "$1.tmp" "$1"
}

send_ntfy() {
    [ -n "$NTFY_URL" ] && [ -n "$NTFY_TOKEN_FILE" ] || return 0
    curl -fsS --max-time 30 \
        -H @<(printf 'Authorization: Bearer %s\n' "$(<"$NTFY_TOKEN_FILE")") \
        -H "Title: $(jq -r .title "$1")" -H "Priority: $(jq -r .priority "$1")" \
        -d "$(jq -r .body "$1")" "$NTFY_URL/$NTFY_TOPIC" >/dev/null
}

send_github() {
    [ -n "$GITHUB_TOKEN_FILE" ] || return 0
    "$REPORT_CMD" "$(jq -r .kind "$1")" "$(jq -r .host "$1")" "$(jq -r .sha "$1")" \
        "$(jq -r .stage "$1")" "$(jq -r .rolled_back "$1")"
}

# Any non-zero exit of a channel (network, 5xx, the report command's 44) keeps the message
# queued; it is removed only once both channels took it.
cmd_deliver() {
    local f undelivered=0
    shopt -s nullglob
    for f in "$OUTBOX"/*.json; do
        if ! jq -e . "$f" >/dev/null 2>&1; then
            # Not retryable: park it so deliver does not fail (and get restarted) forever.
            echo "moving corrupt outbox file $f to bad/" >&2
            mkdir -p "$OUTBOX/bad"
            mv "$f" "$OUTBOX/bad/"
            continue
        fi
        if [ "$(jq -r .ntfy_done "$f")" != true ] && send_ntfy "$f"; then mark_done "$f" ntfy_done; fi
        if [ "$(jq -r .github_done "$f")" != true ] && send_github "$f"; then mark_done "$f" github_done; fi
        if [ "$(jq -r '.ntfy_done and .github_done' "$f")" = true ]; then
            rm -f "$f"
        else
            undelivered=1
        fi
    done
    return "$undelivered"
}

case "${1:-}" in
    condition | pre | post | failed | boot-health | deliver) "cmd_${1//-/_}" ;;
    *)
        echo "usage: server-upgrade-hooks condition|pre|post|failed|boot-health|deliver" >&2
        exit 2
        ;;
esac
