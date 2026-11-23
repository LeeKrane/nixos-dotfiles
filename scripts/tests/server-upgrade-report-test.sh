#!/usr/bin/env bash
# Tests scripts/server-upgrade-report.sh against a fake GitHub API: `curl` on PATH serves JSON
# fixtures and records every request. Run:
#   nix shell nixpkgs#jq nixpkgs#curl --command bash scripts/tests/server-upgrade-report-test.sh
set -euo pipefail

SCRIPT="$(dirname "$(readlink -f "$0")")/../server-upgrade-report.sh"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/bin" "$WORK/fix" "$WORK/log"
printf 'test-token' >"$WORK/token"

# curl stub: logs "METHOD PATH BODY" per request and answers from $FIX/<METHOD>_<PATH>[.N].json,
# the Nth call to that endpoint first, else the endpoint's catch-all, else {}.
command cat >"$WORK/bin/curl" <<'EOF'
#!/usr/bin/env bash
method=GET url="" data=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        -X) method="$2"; shift 2 ;;
        -d) data="$2"; shift 2 ;;
        -H | --max-time | -w) shift 2 ;;
        -*) shift ;;
        *) url="$1"; shift ;;
    esac
done
path="${url#https://api.test}"
printf '%s %s %s\n' "$method" "$path" "$data" >>"$LOG_DIR/requests"
key="$(printf '%s_%s' "$method" "$path" | tr -c 'A-Za-z0-9' _)"
n=$(($(command cat "$FIX/$key.count" 2>/dev/null || echo 0) + 1))
echo "$n" >"$FIX/$key.count"
file="$FIX/$key.$n.json"
[ -f "$file" ] || file="$FIX/$key.json"
if [ -f "$file" ]; then command cat "$file"; else echo '{}'; fi
# like curl -w '\n%{http_code}': 200 unless $key.code says otherwise
printf '\n%s' "$(command cat "$FIX/$key.code" 2>/dev/null || echo 200)"
EOF
chmod +x "$WORK/bin/curl"

failures=0
check() { # check NAME CONDITION...
    local name=$1
    shift
    if "$@"; then echo "ok   $name"; else echo "FAIL $name"; failures=$((failures + 1)); fi
}

# fx METHOD PATH JSON [N]: canned response for the Nth call to the endpoint, or for all calls.
fx() {
    local key
    key="$(printf '%s_%s' "$1" "$2" | tr -c 'A-Za-z0-9' _)"
    printf '%s' "$3" >"$WORK/fix/$key${4:+.$4}.json"
}
# fxcode METHOD PATH CODE: HTTP status the endpoint answers with (default 200).
fxcode() {
    local key
    key="$(printf '%s_%s' "$1" "$2" | tr -c 'A-Za-z0-9' _)"
    printf '%s' "$3" >"$WORK/fix/$key.code"
}
LIST="/repos/a/b/issues?labels=server-upgrade&state=open&per_page=100"
SHA=aaaaaaa1111111111111111111111111111111aa
OLD_SHA=1111111aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa11
T="Server upgrade failed: aaaaaaa"
OLD_T="Server upgrade failed: 1111111"
issue() { jq -nc --argjson n "$1" --arg t "$2" '{number: $n, title: $t}'; }
# marker HOST STATUS: a comment carrying the hidden marker, as the script writes it.
marker() { jq -nc --arg b "<!-- server-upgrade host=$1 sha=$SHA status=$2 -->" '{body: $b}'; }

reset() {
    rm -rf "$WORK/fix" "$WORK/log"
    mkdir -p "$WORK/fix" "$WORK/log"
}
run() { # run KIND HOST [STAGE ROLLED]; RUN_SHA overrides the SHA
    status=0
    env PATH="$WORK/bin:$PATH" FIX="$WORK/fix" LOG_DIR="$WORK/log" \
        GITHUB_TOKEN_FILE="$WORK/token" REPO=a/b API_URL=https://api.test \
        bash "$SCRIPT" "$1" "$2" "${RUN_SHA:-$SHA}" "${3:-}" "${4:-}" >/dev/null 2>"$WORK/log/stderr" || status=$?
}
requested() { grep -qF -- "$1" "$WORK/log/requests"; }
wrote() { grep -qE '^(POST|PATCH) ' "$WORK/log/requests"; }

# failure, no open issue: creates it (labeled), comments with this host's report
reset
fx GET "$LIST" '[]' 1
fx GET "$LIST" "[$(issue 12 "$T")]" 2
fx POST /repos/a/b/issues '{"number":12}'
run failed tarronax build no
check 'new failure: exit 0' [ "$status" -eq 0 ]
check 'new failure: issue created with title' requested "POST /repos/a/b/issues {\"title\":\"$T\""
check 'new failure: labeled' requested '"labels":["server-upgrade"]'
check 'new failure: comment on the new issue' requested 'POST /repos/a/b/issues/12/comments'
check 'new failure: marker in comment' requested "status=failed"
check 'new failure: journal hint' requested 'journalctl -u nixos-upgrade -u server-upgrade-health -n 30'
check 'new failure: no close' eval '! requested PATCH'

# failure, an open issue for the same SHA: only a comment
reset
fx GET "$LIST" "[$(issue 5 "$T")]"
run failed taronychus activation yes
check 'same sha: exit 0' [ "$status" -eq 0 ]
check 'same sha: comment on the open issue' requested 'POST /repos/a/b/issues/5/comments'
check 'same sha: no new issue' eval '! requested "POST /repos/a/b/issues {"'
check 'same sha: no close' eval '! requested PATCH'

# race: another host created issue 11 in the same minute; the newer duplicate (12) closes itself
reset
fx GET "$LIST" '[]' 1
fx GET "$LIST" "[$(issue 11 "$T"),$(issue 12 "$T")]" 2
fx POST /repos/a/b/issues '{"number":12}'
run failed tarritator health no
check 'race: report handed to the older issue' requested 'POST /repos/a/b/issues/11/comments'
check 'race: duplicate closed' requested 'PATCH /repos/a/b/issues/12'
check 'race: older issue stays open' eval '! requested "PATCH /repos/a/b/issues/11"'

# failure on a newer SHA closes the issue of an older cycle (an ancestor) as superseded
reset
fx GET "$LIST" "[$(issue 3 "$OLD_T")]" 1
fx GET "$LIST" "[$(issue 3 "$OLD_T"),$(issue 4 "$T")]" 2
fx POST /repos/a/b/issues '{"number":4}'
fx GET "/repos/a/b/compare/1111111...$SHA" '{"status":"ahead"}'
run failed tarronax build no
check 'superseded: old issue closed' requested 'PATCH /repos/a/b/issues/3'
check 'superseded: comment names the new issue' requested 'Superseded by #4.'
check 'superseded: new issue stays open' eval '! requested "PATCH /repos/a/b/issues/4"'

# a late failure for an OLDER sha must not close the newer sha's issue
reset
fx GET "$LIST" "[$(issue 4 "$T")]" 1
fx GET "$LIST" "[$(issue 4 "$T"),$(issue 6 "$OLD_T")]" 2
fx POST /repos/a/b/issues '{"number":6}'
fx GET "/repos/a/b/compare/aaaaaaa...$OLD_SHA" '{"status":"behind"}'
RUN_SHA=$OLD_SHA run failed tarronax build no
check 'late older failure: exit 0' [ "$status" -eq 0 ]
check 'late older failure: ancestry checked' requested "GET /repos/a/b/compare/aaaaaaa...$OLD_SHA"
check 'late older failure: newer issue stays open' eval '! requested "PATCH /repos/a/b/issues/4"'
check 'late older failure: no supersede comment' eval '! requested "Superseded"'

# compare answers 404 (unknown/unrelated SHA): that issue is left alone, the rest of the flow completes
reset
fx GET "$LIST" "[$(issue 3 "$OLD_T")]" 1
fx GET "$LIST" "[$(issue 3 "$OLD_T"),$(issue 4 "$T")]" 2
fx POST /repos/a/b/issues '{"number":4}'
fx GET "/repos/a/b/compare/1111111...$SHA" '{"message":"Not Found"}'
fxcode GET "/repos/a/b/compare/1111111...$SHA" 404
run failed tarronax build no
check 'compare 404: exit 0' [ "$status" -eq 0 ]
check 'compare 404: report still posted' requested 'POST /repos/a/b/issues/4/comments'
check 'compare 404: old issue untouched' eval '! requested "/issues/3"'

# compare answers 500: non-fatal, the report is posted once and the old issue stays open
reset
fx GET "$LIST" "[$(issue 3 "$OLD_T")]" 1
fx GET "$LIST" "[$(issue 3 "$OLD_T"),$(issue 4 "$T")]" 2
fx POST /repos/a/b/issues '{"number":4}'
fx GET "/repos/a/b/compare/1111111...$SHA" '{}'
fxcode GET "/repos/a/b/compare/1111111...$SHA" 500
run failed tarronax build no
check 'compare 500: exit 0' [ "$status" -eq 0 ]
check 'compare 500: comment posted once' [ "$(grep -c 'POST /repos/a/b/issues/4/comments' "$WORK/log/requests")" -eq 1 ]
check 'compare 500: old issue left open' eval '! requested "/issues/3"'

# a repeated failed call for the same host and SHA does not comment again
reset
fx GET "$LIST" "[$(issue 5 "$T")]"
fx GET "/repos/a/b/issues/5/comments?per_page=100" "[$(marker tarronax failed)]"
run failed tarronax build no
check 'repeat failed: exit 0' [ "$status" -eq 0 ]
check 'repeat failed: no second comment' eval '! wrote'

# recovery with no open issue: nothing is written
reset
fx GET "$LIST" '[]'
run recovered tarronax
check 'recovery, no issue: exit 0' [ "$status" -eq 0 ]
check 'recovery, no issue: no write' eval '! wrote'

# recovery, open issue without a failed marker for this host: nothing is written
reset
fx GET "$LIST" "[$(issue 7 "$T")]"
fx GET "/repos/a/b/issues/7/comments?per_page=100" "[$(marker tarritator failed)]"
run recovered tarronax
check 'recovery, other host only: no write' eval '! wrote'

# recovery while another host still fails: comment, issue stays open
reset
fx GET "$LIST" "[$(issue 7 "$T")]"
fx GET "/repos/a/b/issues/7/comments?per_page=100" "[$(marker tarronax failed),$(marker tarritator failed)]"
run recovered tarronax
check 'recovery, another host failing: comment' requested 'POST /repos/a/b/issues/7/comments'
check 'recovery, another host failing: recovered marker' requested 'status=recovered'
check 'recovery, another host failing: stays open' eval '! requested PATCH'

# the last recovery closes it; an earlier failed marker of the same host does not count
reset
fx GET "$LIST" "[$(issue 7 "$T")]"
fx GET "/repos/a/b/issues/7/comments?per_page=100" "[$(marker tarritator failed),$(marker tarritator recovered),$(marker tarronax failed)]"
run recovered tarronax
check 'last recovery: comment' requested 'POST /repos/a/b/issues/7/comments'
check 'last recovery: closed' requested 'PATCH /repos/a/b/issues/7'

# the API fails: non-zero exit, so the message stays in the outbox
reset
mkdir -p "$WORK/failbin"
printf '#!/usr/bin/env bash\nexit 22\n' >"$WORK/failbin/curl"
chmod +x "$WORK/failbin/curl"
status=0
env PATH="$WORK/failbin:$PATH" GITHUB_TOKEN_FILE="$WORK/token" REPO=a/b API_URL=https://api.test \
    bash "$SCRIPT" failed tarronax "$SHA" build no >/dev/null 2>&1 || status=$?
check 'API failure: non-zero exit' [ "$status" -ne 0 ]

# recovered with the GitHub API down must fail too, not look like "no open issues"
status=0
env PATH="$WORK/failbin:$PATH" GITHUB_TOKEN_FILE="$WORK/token" REPO=a/b API_URL=https://api.test \
    bash "$SCRIPT" recovered tarronax "$SHA" >/dev/null 2>&1 || status=$?
check 'recovered: GitHub API down exits non-zero' [ "$status" -ne 0 ]

echo
if [ "$failures" -eq 0 ]; then echo 'all passed'; else echo "$failures failed"; exit 1; fi
