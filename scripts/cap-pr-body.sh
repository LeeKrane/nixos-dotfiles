#!/usr/bin/env bash
# Usage: cap-pr-body.sh BODY_FILE RUN_URL [MAX_CHARS]
# Shrinks BODY_FILE (printed to stdout) to MAX_CHARS (default 60000) to fit GitHub's 65536-char PR body limit;
# self-test: cap-pr-body.sh --self-test
set -euo pipefail

MAX_DEFAULT=60000
KEEP_ROWS=15

strip_log() {
  awk '
    BEGIN { infence = 0; replaced = 0 }
    /^```$/ {
      if (!infence && !replaced) { infence = 1; next }
      if (infence) {
        infence = 0
        replaced = 1
        print "_Log omitted, see run artifacts for the full `nix flake update` log._"
        next
      }
    }
    infence { next }
    { print }
  '
}

truncate_table() {
  awk -v heading="$1" -v keep="$2" -v url="$3" '
    function note(n) { printf("... %d more rows, see run artifacts: %s\n", n, url) }
    BEGIN { state = 0; rowcount = 0 }
    {
      if (state == 0) { print; if ($0 == heading) state = 1; next }
      if (state == 1) { print; if ($0 == "") state = 2; next }
      if (state == 2) {
        if ($0 ~ /^\| /) { print; state = 3; next }
        print; state = 0; next
      }
      if (state == 3) { print; state = 4; next }
      if (state == 4) {
        if ($0 ~ /^\| /) {
          rowcount++
          if (rowcount <= keep) print
          next
        }
        if (rowcount > keep) note(rowcount - keep)
        print
        state = 0
        rowcount = 0
        next
      }
    }
    END { if (state == 4 && rowcount > keep) note(rowcount - keep) }
  '
}

self_test() {
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  {
    echo '### Package versions'
    echo
    # shellcheck disable=SC2016 # backticks in fixture string, don't expand here
    echo '<details><summary>Transitive inputs and raw `nix flake update` log</summary>'
    echo
    echo '```'
    for i in $(seq 1 2000); do
      echo "log line $i with some padding text to grow the synthetic body substantially"
    done
    echo '```'
    echo '</details>'
    echo
    echo '**Fixed**'
    echo
    echo '| CVE | CVSS | Package | Hosts |'
    echo '| --- | --- | --- | --- |'
    for i in $(seq 1 200); do echo "| CVE-2024-$i | 7.5 | pkg-$i | hosta |"; done
    echo
    echo '**New**'
    echo
    echo '| CVE | CVSS | Package | Hosts |'
    echo '| --- | --- | --- | --- |'
    for i in $(seq 1 200); do echo "| CVE-2025-$i | 9.1 | pkg-$i | hostb |"; done
    echo
    echo '### Local builds'
    echo
    echo 'hosta: no new local builds (3 total)'
  } >"$tmp/body.md"
  before=$(wc -c <"$tmp/body.md")
  "$0" "$tmp/body.md" 'https://example.invalid/run' 60000 >"$tmp/capped.md"
  after=$(wc -c <"$tmp/capped.md")
  echo "self-test: before=$before after=$after max=60000"
  if [ "$after" -le 60000 ]; then
    echo 'self-test: ok, capped body fits'
  else
    echo 'self-test: FAIL, capped body still oversized' >&2
    exit 1
  fi
}

if [ "${1:-}" = "--self-test" ]; then
  self_test
  exit 0
fi

BODY_FILE="${1:?usage: cap-pr-body.sh BODY_FILE RUN_URL [MAX_CHARS]}"
RUN_URL="${2:?usage: cap-pr-body.sh BODY_FILE RUN_URL [MAX_CHARS]}"
MAX_CHARS="${3:-$MAX_DEFAULT}"

work="$(mktemp)"
trap 'rm -f "$work" "$work.next"' EXIT
cp "$BODY_FILE" "$work"

size() { wc -c <"$1"; }

shrink_step() {
  if [ "$(size "$work")" -gt "$MAX_CHARS" ]; then
    "$@" <"$work" >"$work.next"
    mv "$work.next" "$work"
  fi
}

shrink_step strip_log
shrink_step truncate_table '**Fixed**' "$KEEP_ROWS" "$RUN_URL"
shrink_step truncate_table '**New**' "$KEEP_ROWS" "$RUN_URL"

command cat "$work"
