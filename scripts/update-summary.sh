#!/usr/bin/env bash
# Renders the Markdown body pieces for the weekly flake-update pull request
# (.github/workflows/update.yml): a package-version table (from two
# update-versions.nix evaluations), a top-level flake-input table with
# GitHub compare links, and a <details> block holding the changed
# transitive inputs plus the raw `nix flake update` log. Prints Markdown to
# stdout; the workflow wraps it with the gate-result line and the two
# closing notes.
#
# Usage: update-summary.sh OLD_LOCK NEW_LOCK [VERSIONS_BEFORE VERSIONS_AFTER] [RAW_LOG]
#   OLD_LOCK, NEW_LOCK      flake.lock before/after `nix flake update`
#   VERSIONS_BEFORE/_AFTER  optional, name->version JSON (nix eval --json
#                           '.#nixosConfigurations.<host>' --apply
#                           'import scripts/update-versions.nix'); pass both
#                           or neither, the package table is skipped otherwise
#   RAW_LOG                 optional, raw `nix flake update` output, quoted
#                           verbatim in the <details> block
set -euo pipefail

OLD_LOCK="${1:?usage: update-summary.sh OLD_LOCK NEW_LOCK [VERSIONS_BEFORE VERSIONS_AFTER] [RAW_LOG]}"
NEW_LOCK="${2:?usage: update-summary.sh OLD_LOCK NEW_LOCK [VERSIONS_BEFORE VERSIONS_AFTER] [RAW_LOG]}"
VERSIONS_BEFORE="${3:-}"
VERSIONS_AFTER="${4:-}"
RAW_LOG="${5:-}"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

# Walks flake.lock's node graph from its root, naming every reachable input by
# its path (`zen-browser/nixpkgs`, `illogical-flake/nur/flake-parts`, ...). A
# `follows` entry is recorded in flake.lock as an array and introduces no node
# of its own, so it is skipped; a plain string names another node to recurse
# into. Emits { top: [...], trans: [...] }, already-formatted "| ... |" table
# rows for inputs whose locked content changed, top-level (depth 1, declared
# directly in flake.nix) separated from transitive.
cat >"$WORKDIR/lock-diff.jq" <<'JQ'
def walk($nodes; $startInputs):
  def rec($path; $nodeKey):
    [[$path, $nodeKey]] + (
      ($nodes[$nodeKey].inputs // {}) | to_entries | map(
          if (.value | type) == "array" then []
          else rec($path + "/" + .key; .value)
          end
        ) | add // []
    );
  ($startInputs | to_entries | map(
      if (.value | type) == "array" then []
      else rec(.key; .value)
      end
    ) | add // []);

def shortid:
  if (.rev? // null) != null then .rev[0:7]
  elif (.narHash? // null) != null then (.narHash | sub("^sha256-"; "") | .[0:7])
  else "???????"
  end;

def fmtdate:
  if . == null then "-" else (.lastModified | gmtime | strftime("%Y-%m-%d")) end;

def changes($o; $n):
  if $o == null then "added"
  elif $n == null then "removed"
  elif ($o.type == "github" and $n.type == "github") then
    "[`" + ($o | shortid) + "..." + ($n | shortid) + "`](https://github.com/"
      + $n.owner + "/" + $n.repo + "/compare/" + $o.rev + "..." + $n.rev + ")"
  else
    "`" + ($o | shortid) + " → " + ($n | shortid) + "`"
  end;

($old[0]) as $old |
($new[0]) as $new |
($old.nodes[$old.root].inputs) as $oldRoot |
($new.nodes[$new.root].inputs) as $newRoot |
([walk($old.nodes; $oldRoot)[]] | map({(.[0]): $old.nodes[.[1]].locked}) | add // {}) as $oldMap |
([walk($new.nodes; $newRoot)[]] | map({(.[0]): $new.nodes[.[1]].locked}) | add // {}) as $newMap |
(($oldRoot | keys) + ($newRoot | keys) | unique) as $topPaths |
((($oldMap | keys) + ($newMap | keys)) - $topPaths | unique) as $transPaths |
{
  top: [
    $topPaths[] | . as $p | ($oldMap[$p]) as $o | ($newMap[$p]) as $n |
    select($o != $n) |
    ("| " + $p + " | " + ($o | fmtdate) + " | " + ($n | fmtdate) + " | " + changes($o; $n) + " |")
  ],
  trans: [
    $transPaths[] | . as $p | ($oldMap[$p]) as $o | ($newMap[$p]) as $n |
    select($o != $n) |
    ("| `" + $p + "` | " + ($o | fmtdate) + " | " + ($n | fmtdate) + " | " + changes($o; $n) + " |")
  ]
}
JQ

diff_json="$(jq -n --slurpfile old "$OLD_LOCK" --slurpfile new "$NEW_LOCK" -f "$WORKDIR/lock-diff.jq")"

top_rows="$(jq -r '.top[]' <<<"$diff_json")"
trans_rows="$(jq -r '.trans[]' <<<"$diff_json")"

# --- Package versions -------------------------------------------------------
if [ -n "$VERSIONS_BEFORE" ] && [ -n "$VERSIONS_AFTER" ]; then
  version_rows="$(jq -nr \
    --slurpfile before "$VERSIONS_BEFORE" \
    --slurpfile after "$VERSIONS_AFTER" '
      ($before[0]) as $before | ($after[0]) as $after |
      (($before | keys) + ($after | keys) | unique) as $ks |
      $ks[] | . as $k | ($before[$k]) as $b | ($after[$k]) as $a |
      select($b != $a) |
      "| \($k) | \($b // "-") | \($a // "-") |"
    ')"
  if [ -n "$version_rows" ]; then
    echo '### Package versions'
    echo '| Package | Before | After |'
    echo '| --- | --- | --- |'
    echo "$version_rows"
    echo
  fi
fi

# --- Top-level inputs --------------------------------------------------------
if [ -n "$top_rows" ]; then
  echo '### Inputs'
  echo '| Input | From | To | Changes |'
  echo '| --- | --- | --- | --- |'
  echo "$top_rows"
  echo
fi

# --- Transitive inputs and raw log, collapsed -------------------------------
if [ -n "$trans_rows" ] || [ -n "$RAW_LOG" ]; then
  echo '<details><summary>Transitive inputs and raw <code>nix flake update</code> log</summary>'
  echo
  if [ -n "$trans_rows" ]; then
    echo '| Input | From | To | Changes |'
    echo '| --- | --- | --- | --- |'
    echo "$trans_rows"
    echo
  fi
  if [ -n "$RAW_LOG" ]; then
    echo '```'
    command cat "$RAW_LOG"
    echo '```'
  fi
  echo '</details>'
fi
