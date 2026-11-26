#!/usr/bin/env bash
# Usage: server-upgrade-report.sh failed|recovered HOST SHA [STAGE] [ROLLED_BACK]
#   GITHUB_TOKEN_FILE  file with a token that has Issues: read and write   required
#   REPO               owner/name, default LeeKrane/nixos-dotfiles
#   API_URL            default https://api.github.com (tests point it elsewhere)
set -euo pipefail

kind="${1:?usage: server-upgrade-report.sh failed|recovered HOST SHA [STAGE] [ROLLED_BACK]}"
host="${2:?HOST missing}"
sha="${3:?SHA missing}"
stage="${4:--}"
rolled="${5:--}"
: "${GITHUB_TOKEN_FILE:?GITHUB_TOKEN_FILE must be set}"
REPO="${REPO:-LeeKrane/nixos-dotfiles}"
API_URL="${API_URL:-https://api.github.com}"
LABEL=server-upgrade

token="$(<"$GITHUB_TOKEN_FILE")"
title="Server upgrade failed: ${sha:0:7}"

# The token goes in a header file so it never shows in the process list.
api() {
    local method="$1" path="$2"
    shift 2
    local body=() out code
    if [ "$#" -gt 0 ]; then body=(-d "$1"); fi
    out="$(curl -sS --max-time 30 -X "$method" -w '\n%{http_code}' \
        -H @<(printf 'Authorization: Bearer %s\n' "$token") \
        -H 'Accept: application/vnd.github+json' \
        -H 'X-GitHub-Api-Version: 2022-11-28' \
        "${body[@]}" "$API_URL/repos/$REPO$path")" || return
    code="${out##*$'\n'}"
    case "$code" in
        2??) printf '%s\n' "${out%$'\n'*}" ;;
        404 | 422) return 44 ;; # unknown ref or unrelated SHAs, see on_failed
        *) return 22 ;;
    esac
}

# The issues endpoint also lists pull requests.
open_issues() {
    api GET "/issues?labels=$LABEL&state=open&per_page=100" | jq '[.[] | select(.pull_request == null)]'
}

issue_for_sha() {
    jq -r --arg t "$title" '[.[] | select(.title == $t) | .number] | min // empty'
}

latest_markers() {
    api GET "/issues/$1/comments?per_page=100" | jq '
        [.[].body
          | capture("<!-- server-upgrade host=(?<host>[^ ]+) sha=(?<sha>[^ ]+) status=(?<status>failed|recovered) -->")]
        | group_by(.host) | map(last)'
}

# shellcheck disable=SC2016 # literal backticks for Markdown
report_body() {
    printf '<!-- server-upgrade host=%s sha=%s status=%s -->\n' "$host" "$sha" "$1"
    if [ "$1" = failed ]; then
        printf '**%s** failed to upgrade to `%s` at stage `%s` (rolled back: %s).\n\n' "$host" "${sha:0:7}" "$stage" "$rolled"
        printf 'On the host: `journalctl -u nixos-upgrade -u server-upgrade-health -n 30`.\n'
    else
        printf '**%s** recovered on `%s`.\n' "$host" "${sha:0:7}"
    fi
}

comment() {
    api POST "/issues/$1/comments" "$(jq -nc --arg b "$2" '{body: $b}')" >/dev/null
}

close_issue() {
    api PATCH "/issues/$1" '{"state":"closed","state_reason":"not_planned"}' >/dev/null
}

on_failed() {
    local issues n created
    issues="$(open_issues)"
    n="$(issue_for_sha <<<"$issues")"
    if [ -n "$n" ]; then
        # A retried delivery must not repeat this host's comment.
        if ! latest_markers "$n" | jq -e --arg h "$host" --arg s "$sha" \
            'any(.[]; .host == $h and .sha == $s and .status == "failed")' >/dev/null; then
            comment "$n" "$(report_body failed)"
        fi
    else
        created="$(api POST /issues "$(jq -nc --arg t "$title" --arg l "$LABEL" \
            --arg b "The automatic upgrade of the servers to \`$sha\` failed. Each host reports in a comment below." \
            '{title: $t, body: $b, labels: [$l]}')" | jq -r .number)"
        comment "$created" "$(report_body failed)"
        # Another host may have created an issue for this SHA at the same time: the lowest number wins, a newer duplicate closes itself.
        issues="$(open_issues)"
        n="$(issue_for_sha <<<"$issues")"
        n="${n:-$created}"
        if [ "$n" != "$created" ]; then
            comment "$n" "$(report_body failed)"
            comment "$created" "Duplicate of #$n."
            close_issue "$created"
        fi
    fi
    # Close only issues whose SHA is an ancestor of this one, so a late report for an older SHA never closes a newer issue.
    local old old_sha rc cmp
    while read -r old old_sha; do
        rc=0
        cmp="$(api GET "/compare/$old_sha...$sha")" || rc=$?
        # Any compare error leaves that issue open: the report is already posted, and failing here would make deliver repost it forever.
        if [ "$rc" -ne 0 ]; then
            echo "compare $old_sha...$sha failed (rc $rc), leaving #$old open" >&2
            continue
        fi
        if [ "$rc" -eq 0 ] && [ "$(jq -r .status <<<"$cmp")" = ahead ]; then
            comment "$old" "Superseded by #$n."
            close_issue "$old"
        fi
    done < <(jq -r --arg t "$title" '.[] | select(.title != $t) | "\(.number) \(.title | capture("^Server upgrade failed: (?<s>[0-9a-f]+)$").s? // empty)"' <<<"$issues" | awk 'NF == 2')
}

on_recovered() {
    local issues n markers
    issues="$(open_issues)"
    while read -r n; do
        markers="$(latest_markers "$n")"
        if jq -e --arg h "$host" 'any(.[]; .host == $h and .status == "failed")' <<<"$markers" >/dev/null; then
            comment "$n" "$(report_body recovered)"
            if jq -e --arg h "$host" 'any(.[]; .host != $h and .status == "failed") | not' <<<"$markers" >/dev/null; then
                close_issue "$n"
            fi
        fi
    done < <(jq -r '.[].number' <<<"$issues")
}

case "$kind" in
    failed) on_failed ;;
    recovered) on_recovered ;;
    *)
        echo "unknown kind: $kind" >&2
        exit 2
        ;;
esac
