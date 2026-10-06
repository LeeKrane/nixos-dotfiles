#!/usr/bin/env bash
# Raises a desktop notification when the weekly update workflow has an
# update pull request open, once per pushed head commit. Run by the
# flake-update-notify user timer (modules/home/flake-update-notify.nix).
#   REPO                   owner/name                                   required
#   BRANCH                 head branch of the pull request              required
#   PULLS_URL              overrides the API URL, for tests             optional
#   NOTIFY_FAIL_THRESHOLD  overrides the notify-send fail-fast          optional
#                          threshold below (seconds), for tests
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

# Prints the body's one-line security status to append as the notification's
# last line, with any Markdown link stripped down to its text:
#   - "### Security" heading present (scripts/security-summary.sh ran): its
#     one-line summary sentence -- the first non-blank line up to the next
#     "#" heading, one of "No CVE changes", "N CVEs fixed, M new" (singular
#     "CVE" when N or M, independently, is 1), "N CVEs fixed" or "M new
#     CVEs". Nothing if the heading has no sentence before the next heading.
#   - no heading but a "Security scan failed (...)" line (the security job
#     itself failed, .github/workflows/update.yml): that line, with its
#     "([run](...))" link stripped down to plain text.
#   - neither: empty output.
security_sentence() {
    awk '
        $0 == "### Security" { found = 1; next }
        found && /^#/ { exit }
        found && NF == 0 { next }
        found { print; exit }
        /^Security scan failed/ { print; exit }
    ' | sed -E 's/ \(\[run\]\([^)]*\)\)$//'
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

# Probes the notification daemon before writing state, so a daemon that
# isn't up yet (racing the session at login) retries without a popup ever
# having been shown. Exits 1 with state untouched: the systemd unit's
# Restart=on-failure/RestartSec=2min (modules/home/flake-update-notify.nix)
# retries this, same as a curl failure above.
if ! busctl --user call org.freedesktop.Notifications /org/freedesktop/Notifications \
    org.freedesktop.Notifications GetServerInformation >/dev/null; then
    echo "flake-update-notify: notification daemon not reachable" >&2
    exit 1
fi

summary="Flake update ready (#$number)"
urgency=normal
case "$title" in
    '[gate failing]'*)
        summary="Flake update ready (#$number) (gate failing)"
        urgency=critical
        ;;
esac

rows=$(table_rows '### Package versions' <<<"$body")
if [ -n "$rows" ]; then
    # Caps at the first max_pkgs *distinct packages*, not rows: a split
    # package (the 4-column Hosts form below) spans several consecutive rows
    # sharing one package name, and all of them count as one package against
    # the cap. This is a guard, not a routine case -- update-versions.nix
    # tracks a fixed small set of packages, so the table is normally well
    # under the cap; it only bites a lockstep nixpkgs bump that happens to
    # touch most of that set at once.
    text=$(awk -F'|' -v max_pkgs=5 '
        function flush() {
            if (count != 0 && count <= max_pkgs) print buf
        }
        {
            # NF-1 is the index of the last real column: 4 for the plain
            # "Package | Before | After" table, 5 when a 4-column "Hosts"
            # column (scripts/update-summary.sh, a package split
            # differently across hosts) is present.
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

# Append the security status (see security_sentence above) as the body's
# last line, when there is one.
security=$(security_sentence <<<"$body")
if [ -n "$security" ]; then
    text="$text
$security"
fi

# Written before notifying, so a dismissed or ignored notification does not
# repeat. The daemon already answered the probe above, so a notify-send
# failure past this point isn't "not up yet" -- it's timed below instead, to
# tell a popup that was never shown apart from one that was. Expire time 0
# keeps the popup on screen until dismissed.
mkdir -p "$state_dir"
printf '%s\n%s\n' "$sha" "$seen_hash" >"$state_file"

# --wait blocks until the popup is closed, so a real notification takes far
# longer than a failure before the daemon ever rendered anything. A
# notify-send failure within $fail_threshold seconds is read as the latter:
# no popup was shown, so state is removed and this exits 1 to retry, same as
# the probe above. Past that threshold, a popup was almost certainly shown
# and something else then went wrong; retrying would risk showing it twice,
# so state is kept and this exits 0 instead.
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
    # Via a transient unit, so the browser xdg-open launches outlives this
    # oneshot unit's cgroup instead of being killed when it deactivates.
    systemd-run --user --quiet --collect xdg-open "$html_url"
fi
