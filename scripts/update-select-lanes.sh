#!/usr/bin/env bash
#   EVENT          schedule | workflow_dispatch | push
#   LANE_INPUT     dispatch only: both (default) | servers | desktops
#   POLL_INTERVAL  seconds between mergeability polls (default 10)
#   POLL_DEADLINE  seconds to keep polling an UNKNOWN answer (default 120)
# On push only lanes whose open same-repo PR now conflicts are selected: `mergeable` is computed lazily, so UNKNOWN is polled until the deadline,
# then skipped with a warning.
set -euo pipefail

: "${EVENT:?EVENT must be set}"
case "$EVENT" in
    schedule)
        echo '["servers","desktops"]'
        exit 0
        ;;
    workflow_dispatch)
        case "${LANE_INPUT:-both}" in
            both) echo '["servers","desktops"]' ;;
            servers | desktops) printf '["%s"]\n' "$LANE_INPUT" ;;
            *)
                echo "unknown lane: $LANE_INPUT" >&2
                exit 1
                ;;
        esac
        exit 0
        ;;
    push) ;;
    *)
        echo "unsupported event: $EVENT" >&2
        exit 1
        ;;
esac

interval="${POLL_INTERVAL:-10}"
deadline="${POLL_DEADLINE:-120}"

# NONE when the lane has no open PR from this repo (fork PRs with the same branch name don't count).
mergeable() {
    gh pr list --head "ci/flake-update-$1" --base main --state open \
        --json mergeable,isCrossRepository \
        --jq '[.[] | select(.isCrossRepository | not)][0].mergeable // "NONE"'
}

selected=()
for lane in servers desktops; do
    waited=0
    while :; do
        state="$(mergeable "$lane")"
        if [ "$state" != UNKNOWN ] || [ "$waited" -ge "$deadline" ]; then break; fi
        sleep "$interval"
        waited=$((waited + interval))
    done
    case "$state" in
        CONFLICTING) selected+=("$lane") ;;
        UNKNOWN) echo "::warning::$lane update PR still UNKNOWN after ${deadline}s, not refreshed" >&2 ;;
    esac
done
jq -cn '$ARGS.positional' --args "${selected[@]}"
