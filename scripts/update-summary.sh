#!/usr/bin/env bash
# Usage: update-summary.sh OLD_LOCK NEW_LOCK [VERSIONS_BEFORE VERSIONS_AFTER] [RAW_LOG]
#   VERSIONS_BEFORE/_AFTER  host->name->version JSON from update-versions.nix; pass both or neither
#   RAW_LOG                 raw `nix flake update` output, quoted in the <details> block
#   HOST_ROLES              optional env, {host: role} JSON for every flake host: collapses host lists
set -euo pipefail
LIB="$(dirname "$(readlink -f "$0")")/lib"

OLD_LOCK="${1:?usage: update-summary.sh OLD_LOCK NEW_LOCK [VERSIONS_BEFORE VERSIONS_AFTER] [RAW_LOG]}"
NEW_LOCK="${2:?usage: update-summary.sh OLD_LOCK NEW_LOCK [VERSIONS_BEFORE VERSIONS_AFTER] [RAW_LOG]}"
VERSIONS_BEFORE="${3:-}"
VERSIONS_AFTER="${4:-}"
RAW_LOG="${5:-}"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

# Walks flake.lock's node graph from the root, naming reachable inputs by path. A `follows` entry (an array in flake.lock) has no node
# and is skipped. Emits { top: [...], trans: [...] } table rows for changed inputs, top-level (declared in flake.nix) apart from transitive.
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
  # A path/file input's locked node has no lastModified: render "-" instead of erroring on gmtime(null).
  if (. == null) or (.lastModified == null) then "-"
  else (.lastModified | gmtime | strftime("%Y-%m-%d"))
  end;

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

cat >"$WORKDIR/version-diff.jq" <<'JQ'
include "collapse-hosts";
($before[0]) as $before |
($after[0]) as $after |
($before | keys) as $hosts |
(
  [$hosts[] | ($before[.] // {} | keys)] + [$hosts[] | ($after[.] // {} | keys)]
  | add // [] | unique
) as $pkgs |
[
  $pkgs[] | . as $p |
  (
    [
      $hosts[] | . as $h |
      { host: $h, before: (($before[$h] // {})[$p] // null), after: (($after[$h] // {})[$p] // null) }
    ] | map(select(.before != .after))
  ) as $changes |
  select(($changes | length) > 0) |
  {
    package: $p,
    groups: (
      $changes
      | group_by([.before, .after])
      | map({ before: .[0].before, after: .[0].after,
              hosts: (map(.host) | if $roles == null then join(", ") else collapse_hosts($roles) end) })
    ),
  }
] as $packages |
# With HOST_ROLES (CI), the Hosts column is always shown: a lane's table covers only the hosts it changed.
{ needsHosts: ($roles != null or ($packages | any(.groups | length > 1))), packages: $packages }
JQ

diff_json="$(jq -n --slurpfile old "$OLD_LOCK" --slurpfile new "$NEW_LOCK" -f "$WORKDIR/lock-diff.jq")"

top_rows="$(jq -r '.top[]' <<<"$diff_json")"
trans_rows="$(jq -r '.trans[]' <<<"$diff_json")"

# Package versions
if [ -n "$VERSIONS_BEFORE" ] && [ -n "$VERSIONS_AFTER" ]; then
  version_diff="$(jq -n -L "$LIB" \
    --argjson roles "${HOST_ROLES:-null}" \
    --slurpfile before "$VERSIONS_BEFORE" \
    --slurpfile after "$VERSIONS_AFTER" -f "$WORKDIR/version-diff.jq")"
  needs_hosts="$(jq -r '.needsHosts' <<<"$version_diff")"
  if [ "$needs_hosts" = true ]; then
    version_rows="$(jq -r '
      .packages[] | .package as $p | .groups[] |
      "| \($p) | \(.before // "-") | \(.after // "-") | \(.hosts) |"
    ' <<<"$version_diff")"
  else
    version_rows="$(jq -r '
      .packages[] | .package as $p | .groups[0] as $g |
      "| \($p) | \($g.before // "-") | \($g.after // "-") |"
    ' <<<"$version_diff")"
  fi
  if [ -n "$version_rows" ]; then
    echo '### Package versions'
    if [ "$needs_hosts" = true ]; then
      echo '| Package | Before | After | Hosts |'
      echo '| --- | --- | --- | --- |'
    else
      echo '| Package | Before | After |'
      echo '| --- | --- | --- |'
    fi
    echo "$version_rows"
    echo
  fi
fi

# Top-level inputs
if [ -n "$top_rows" ]; then
  echo '### Inputs'
  echo '| Input | From | To | Changes |'
  echo '| --- | --- | --- | --- |'
  echo "$top_rows"
  echo
fi

# Transitive inputs and raw log
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
    # The raw log interleaves `nix flake update` output with git's \r-updated fetch progress: split on \r, keep the lock-file warning, "• Updated input"
    # lines, their quoted refs and the claude-code bump. grep finding nothing is not a failure.
    keep_pattern="^(warning: |• |    '|  → |claude-code )"
    tr '\r' '\n' <"$RAW_LOG" | grep -E "$keep_pattern" || true
    echo '```'
  fi
  echo '</details>'
fi
