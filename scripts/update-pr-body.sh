#!/usr/bin/env bash
# Writes the body of a weekly update lane's pull request (.github/workflows/update-lane.yml,
# pr job) to BODY_FILE and prints its title.
#   update-pr-body.sh BODY_FILE
# Env:
#   LANE              servers | desktops
#   RESULT            check.yml's result (success, failure, ...)
#   SECURITY_RESULT   the security job's result (success, failure, skipped, ...)
#   RUN_URL           this workflow run's URL
#   HOSTS             JSON list of the hosts whose toplevel drv the update changed
#   ROLES             {host: role} JSON for every flake host
#   SUMMARY           rendered update summary (scripts/update-summary.sh)
#   WARNINGS          optional: eval-warnings.json, {host: {new, existing}} for the changed hosts
#   SECURITY_SUMMARY  rendered security summary; read only when SECURITY_RESULT is success
set -euo pipefail

BODY_FILE="${1:?usage: update-pr-body.sh BODY_FILE}"
SCRIPTS="$(dirname "$(readlink -f "$0")")"
meta="$("$SCRIPTS/update-lane-meta.sh" "$LANE")"
title="$(sed -n 's/^title=//p' <<<"$meta")"
switch_host="$(sed -n 's/^switch_host=//p' <<<"$meta")"

if [ "$RESULT" != success ]; then
    title="[gate failing] $title"
fi
case "$RESULT" in
    success) gate='✅ passed' ;;
    failure) gate='❌ failing' ;;
    *) gate="$RESULT" ;;
esac
# Servers this update changes, in either lane (desktop-lane bumps reach servers through
# unstable.codegraph in modules/home/server). promote.yml moves deploy on any green main
# commit, so merging upgrades exactly these.
servers_hit="$(jq -rn -L "$SCRIPTS/lib" --argjson roles "$ROLES" --argjson hosts "$HOSTS" \
    'include "collapse-hosts"; [$hosts[] | select($roles[.] == "server")] | collapse_hosts($roles)')"

# "Eval warnings" section from the WARNINGS file ({host: {new, existing}}, see
# lib/warnings-diff.jq): new ones per host group, existing ones folded away. Empty when
# WARNINGS is unset or lists nothing.
warnings=''
if [ -s "${WARNINGS:-}" ]; then
    warnings="$(jq -rn -L "$SCRIPTS/lib" --argjson roles "$ROLES" --slurpfile w "$WARNINGS" '
        include "collapse-hosts";
        def groups(f): to_entries | map(select(.value[f] | length > 0)) | group_by(.value[f])
            | map({hosts: map(.key), list: .[0].value[f]});
        def bullets: .list | map("- " + .) | join("\n");
        ($w[0] | groups("new")) as $new | ($w[0] | groups("existing")) as $old
        | if ($new + $old | length) == 0 then empty else
            "### Eval warnings",
            ($new[] | "\nNew on \(.hosts | collapse_hosts($roles)):\n\(bullets)"),
            (if ($old | length) > 0 then
                "\n<details><summary>Existing warnings</summary>",
                ($old[] | "\n\(.hosts | collapse_hosts($roles)):\n\(bullets)"),
                "\n</details>"
            else empty end)
          end')"
fi

{
    if [ -n "$servers_hit" ]; then
        echo "**Merging deploys to: $servers_hit (promote.yml moves deploy; they upgrade within about an hour).**"
        echo
    fi
    echo "Gate: $gate ([run]($RUN_URL))"
    echo
    if [ "$HOSTS" = '[]' ]; then
        echo 'No host closure changed.'
        echo
    fi
    command cat "$SUMMARY"
    echo
    if [ "$SECURITY_RESULT" = success ]; then
        command cat "$SECURITY_SUMMARY"
        echo
        echo "Full local-build logs: \`local-builds-$LANE\` artifact on [this run]($RUN_URL)."
    elif [ "$SECURITY_RESULT" != skipped ]; then
        echo "Security scan failed ([run]($RUN_URL))"
    fi
    echo
    if [ -n "$warnings" ]; then
        echo "$warnings"
        echo
    fi
    echo 'CI checks eval only. Before merging, on one machine, run:'
    echo
    # Two fenced blocks, so GitHub gives each command its own copy button.
    # shellcheck disable=SC2016 # literal backticks for Markdown
    printf '```sh\n%s\n```\n\n```sh\n%s\n```\n' \
        "git fetch origin ci/flake-update-$LANE && git switch -C ci/flake-update-$LANE FETCH_HEAD" \
        "just switch $switch_host"
    echo
    echo 'Checks do not appear on this pull request: it is opened with GITHUB_TOKEN, which triggers no workflows. Merging runs the gate on main.'
} >"$BODY_FILE"
echo "$title"
