#!/usr/bin/env bash
# Env: REPO and BRANCH (required); LABEL (summary prefix, default "Flake update"); PULLS_URL and NOTIFY_FAIL_THRESHOLD (seconds), for tests.
set -euo pipefail

: "${REPO:?REPO must be owner/name}"
: "${BRANCH:?BRANCH must be set}"

url="${PULLS_URL:-https://api.github.com/repos/$REPO/pulls?head=${REPO%%/*}:$BRANCH&state=open}"
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/flake-update-notify"
# One state file per branch, so each update lane dedupes alone.
state_file="$state_dir/last-seen-$(printf '%s' "$BRANCH" | tr -c 'A-Za-z0-9._-' -)"
label="${LABEL:-Flake update}"

table_rows() {
    awk -v heading="$1" '
        $0 == heading { in_section = 1; next }
        in_section && /^#/ { exit }
        in_section && /^\|/ { if (++rows > 2) print; next }
        in_section && rows { exit }
    '
}

security_sentence() {
    awk '
        $0 == "### Security" { found = 1; next }
        found && /^#/ { exit }
        found && NF == 0 { next }
        found { print; exit }
        /^Security scan failed/ { print; exit }
    ' | sed -E 's/ \(\[run\]\([^)]*\)\)$//'
}

pulls=$(curl -fsSL --max-time 30 -H 'Accept: application/vnd.github+json' "$url")

if [ "$(jq 'length' <<<"$pulls")" -eq 0 ]; then
    rm -f "$state_file"
    exit 0
fi

sha=$(jq -r '.[0].head.sha' <<<"$pulls")
number=$(jq -r '.[0].number' <<<"$pulls")
html_url=$(jq -r '.[0].html_url' <<<"$pulls")
title=$(jq -r '.[0].title' <<<"$pulls")
body=$(jq -r '.[0].body // ""' <<<"$pulls" | tr -d '\r')

# Dedupe on head SHA plus a hash of number+title+body: the update job force-pushes before the pr job rewrites the PR, so a run in
# between sees the new SHA with last week's body, and the later rewrite must still notify.
seen_hash=$(printf '%s\n%s\n%s' "$number" "$title" "$body" | sha256sum | cut -d' ' -f1)
if [ -f "$state_file" ] \
    && [ "$(sed -n '1p' "$state_file")" = "$sha" ] \
    && [ "$(sed -n '2p' "$state_file")" = "$seen_hash" ]; then
    exit 0
fi

if ! busctl --user call org.freedesktop.Notifications /org/freedesktop/Notifications \
    org.freedesktop.Notifications GetServerInformation >/dev/null; then
    echo "flake-update-notify: notification daemon not reachable" >&2
    exit 1
fi

summary="$label ready (#$number)"
urgency=normal
case "$title" in
    '[gate failing]'*)
        summary="$label ready (#$number) (gate failing)"
        urgency=critical
        ;;
esac

rows=$(table_rows '### Package versions' <<<"$body")
if [ -n "$rows" ]; then
    # Caps at max_pkgs distinct packages, not rows: a split package (4-column Hosts form) spans several rows.
    text=$(awk -F'|' -v max_pkgs=5 '
        function flush() {
            if (count != 0 && count <= max_pkgs) print buf
        }
        {
            # NF-1 is the last real column: 4 for "Package | Before | After", 5 with a Hosts column.
            last = NF - 1
            for (i = 2; i <= last; i++) gsub(/^[ \t`]+|[ \t`]+$/, "", $i)
            line = $2 " " $3 " → " $4
            if (last >= 5) line = line " (" $5 ")"
            if ($2 != pkg) {
                flush()
                count++
                pkg = $2
                buf = line
            } else {
                buf = buf "\n" line
            }
        }
        END {
            flush()
            if (count > max_pkgs) printf "...and %d more\n", count - max_pkgs
        }
    ' <<<"$rows")
else
    inputs=$(table_rows '### Inputs' <<<"$body" | wc -l)
    if [ "$inputs" -gt 0 ]; then text="$inputs inputs updated"; else text=$title; fi
fi

security=$(security_sentence <<<"$body")
if [ -n "$security" ]; then
    text="$text
$security"
fi

# Written before notifying so a dismissed notification does not repeat; expire time 0 keeps the popup until dismissed.
mkdir -p "$state_dir"
printf '%s\n%s\n' "$sha" "$seen_hash" >"$state_file"

# --wait blocks until the popup closes, so a notify-send failure within $fail_threshold seconds means no popup was shown: remove state and
# exit 1 to retry. A later failure keeps state and exits 0, as retrying could show the popup twice.
fail_threshold="${NOTIFY_FAIL_THRESHOLD:-2}"
notify_start=$SECONDS
if ! action=$(notify-send -a Dotfiles -u "$urgency" --action=open='Open PR' --expire-time=0 --hint=boolean:x-ii-expanded:true --wait "$summary" "$text"); then
    if [ "$((SECONDS - notify_start))" -lt "$fail_threshold" ]; then
        rm -f "$state_file"
        echo "flake-update-notify: notify-send failed quickly, assuming no popup was shown" >&2
        exit 1
    fi
    echo "flake-update-notify: notify-send failed after a delay, assuming a popup was shown, state kept" >&2
    exit 0
fi
if [ "$action" = open ]; then
    # Transient unit, so the browser xdg-open launches outlives this oneshot unit's cgroup.
    systemd-run --user --quiet --collect xdg-open "$html_url"
fi
