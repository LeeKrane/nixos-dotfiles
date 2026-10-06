#!/usr/bin/env bash
# Raises a desktop notification when the weekly update workflow has an
# update pull request open, once per pushed head commit. Run by the
# flake-update-notify user timer (modules/home/flake-update-notify.nix).
#   REPO       owner/name                        required
#   BRANCH     head branch of the pull request   required
#   PULLS_URL  overrides the API URL, for tests  optional
set -euo pipefail

: "${REPO:?REPO must be owner/name}"
: "${BRANCH:?BRANCH must be set}"

url="${PULLS_URL:-https://api.github.com/repos/$REPO/pulls?head=${REPO%%/*}:$BRANCH&state=open}"
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/flake-update-notify"
state_file="$state_dir/last-seen"

# Prints the data rows of the Markdown table under the heading $1, without
# its header and separator rows.
table_rows() {
    awk -v heading="$1" '
        $0 == heading { in_section = 1; next }
        in_section && /^#/ { exit }
        in_section && /^\|/ { if (++rows > 2) print; next }
        in_section && rows { exit }
    '
}

# An error here exits non-zero through set -e: no notification, state
# untouched, the next timer run retries.
pulls=$(curl -fsSL --max-time 30 -H 'Accept: application/vnd.github+json' "$url")

if [ "$(jq 'length' <<<"$pulls")" -eq 0 ]; then
    # Forget the last head, so a reopened pull request notifies again.
    rm -f "$state_file"
    exit 0
fi

sha=$(jq -r '.[0].head.sha' <<<"$pulls")
number=$(jq -r '.[0].number' <<<"$pulls")
html_url=$(jq -r '.[0].html_url' <<<"$pulls")
title=$(jq -r '.[0].title' <<<"$pulls")
body=$(jq -r '.[0].body // ""' <<<"$pulls" | tr -d '\r')

# Dedupe on head SHA plus a hash of number+title+body, not SHA alone: the
# update job force-pushes before the pr job rewrites the PR in place, so a run
# in between sees the new SHA with last week's body, and the later rewrite must
# still notify.
seen_hash=$(printf '%s\n%s\n%s' "$number" "$title" "$body" | sha256sum | cut -d' ' -f1)
if [ -f "$state_file" ] \
    && [ "$(sed -n '1p' "$state_file")" = "$sha" ] \
    && [ "$(sed -n '2p' "$state_file")" = "$seen_hash" ]; then
    exit 0
fi

summary='Flake update ready'
urgency=normal
case "$title" in
    '[gate failing]'*)
        summary='Flake update ready (gate failing)'
        urgency=critical
        ;;
esac

text=$(table_rows '### Package versions' <<<"$body" | awk -F'|' '{
    # NF-1 is the index of the last real column: 4 for the plain
    # "Package | Before | After" table, 5 when a 4-column "Hosts" column
    # (scripts/update-summary.sh, a package split differently across hosts)
    # is present.
    last = NF - 1
    for (i = 2; i <= last; i++) gsub(/^[ \t`]+|[ \t`]+$/, "", $i)
    line = $2 " " $3 " → " $4
    if (last >= 5) line = line " (" $5 ")"
    print line
}')
if [ -z "$text" ]; then
    inputs=$(table_rows '### Inputs' <<<"$body" | wc -l)
    if [ "$inputs" -gt 0 ]; then text="$inputs inputs updated"; else text=$title; fi
fi

# Written before notifying, so a dismissed or ignored notification does not
# repeat. Removed again if notify-send fails, so that run is retried. Expire
# time 0 keeps the popup on screen until dismissed.
mkdir -p "$state_dir"
printf '%s\n%s\n' "$sha" "$seen_hash" >"$state_file"

if ! action=$(notify-send -a Dotfiles -u "$urgency" --action=open='Open PR' --expire-time=0 --hint=boolean:x-ii-expanded:true --wait "$summary" "$text"); then
    rm -f "$state_file"
    exit 1
fi
if [ "$action" = open ]; then
    # Via a transient unit, so the browser xdg-open launches outlives this
    # oneshot unit's cgroup instead of being killed when it deactivates.
    systemd-run --user --quiet --collect xdg-open "$html_url"
fi
