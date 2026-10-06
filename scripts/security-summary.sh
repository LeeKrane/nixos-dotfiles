#!/usr/bin/env bash
# Renders the Markdown body pieces for the weekly flake-update pull request's
# security report (.github/workflows/update.yml, `security` job): a CVE diff
# between vulnix scans of each host's toplevel derivation before/after
# `nix flake update`, and a count of local builds that are new since main,
# per host, from `nix build --dry-run`. Prints Markdown to stdout. CVEs are
# reported here only, never gating the PR or its title.
#
# Usage: security-summary.sh WORKDIR HOST...
#   WORKDIR  directory holding, per HOST:
#              vulnix-before-<host>.json  `vulnix -j` output, pre-update drv
#              vulnix-after-<host>.json   `vulnix -j` output, post-update drv
#              build-before-<host>.log    raw `nix build --dry-run` output,
#                                         pre-update drv
#              build-after-<host>.log     raw `nix build --dry-run` output,
#                                         post-update drv
#              build-before-<host>.failed  present if the pre-update dry-run
#                                           itself failed (not just found
#                                           builds)
#              build-after-<host>.failed   same, post-update drv
#   HOST...  one or more host names, in display order
set -euo pipefail

WORKDIR="${1:?usage: security-summary.sh WORKDIR HOST...}"
shift
HOSTS=("$@")
if [ "${#HOSTS[@]}" -eq 0 ]; then
  echo "usage: security-summary.sh WORKDIR HOST..." >&2
  exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# --- Flatten each host's vulnix run to one row per (cve, package, version) -
# vulnix -j only lists derivations with at least one active (non-whitelisted)
# CVE, each carrying affected_by (CVE ids) and cvssv3_basescore (CVE id ->
# score; absent when NVD has no CVSSv3 score for it).
cat >"$WORK/flatten.jq" <<'JQ'
[
  .[] as $d |
  ($d.pname // $d.name) as $pkg |
  ($d.version // "") as $ver |
  ($d.affected_by // [])[] as $cve |
  {
    host: $host,
    cve: $cve,
    cvss: (($d.cvssv3_basescore // {})[$cve] // 0),
    package: $pkg,
    version: $ver,
  }
]
JQ

before_flat="$WORK/before-flat.json"
after_flat="$WORK/after-flat.json"
echo '[]' >"$before_flat"
echo '[]' >"$after_flat"
for host in "${HOSTS[@]}"; do
  for state in before after; do
    src="$WORKDIR/vulnix-$state-$host.json"
    dst="$WORK/$state-flat.json"
    [ -f "$src" ] || src="$WORK/empty.json"
    [ -f "$src" ] || echo '[]' >"$WORK/empty.json"
    jq --arg host "$host" -f "$WORK/flatten.jq" "$src" >"$WORK/$state-$host.json"
    jq -s 'add' "$dst" "$WORK/$state-$host.json" >"$WORK/$state-flat.next.json"
    mv "$WORK/$state-flat.next.json" "$dst"
  done
done

# --- Diff: per host, which (cve, package) pairs are new/gone ---------------
# Keyed on (host, cve, package), not version: a version bump that leaves the
# same CVE unfixed on the same package must show as neither new nor fixed.
cat >"$WORK/diff.jq" <<'JQ'
def tkey: [.cve, .package];

($before[0]) as $before |
($after[0]) as $after |
($before + $after | map(.host) | unique) as $hosts |
(
  [
    $hosts[] as $h |
    ($before | map(select(.host == $h) | tkey)) as $beforeKeys |
    ($after[] | select(.host == $h)) |
    select((tkey) as $k | ($beforeKeys | any(. == $k)) | not)
  ]
) as $newFlat |
(
  [
    $hosts[] as $h |
    ($after | map(select(.host == $h) | tkey)) as $afterKeys |
    ($before[] | select(.host == $h)) |
    select((tkey) as $k | ($afterKeys | any(. == $k)) | not)
  ]
) as $fixedFlat |
# $flat rows for the "new" side come from $after (the version on the host
# today) and rows for the "fixed" side come from $before (the version that
# carried the CVE before the update), so .version is already the right side
# per caller; group it into one deduplicated, comma-joined string in case it
# somehow differs across the hosts a group spans.
def grouped($flat):
  $flat
  | group_by([.cve, .package])
  | map({
      cve: .[0].cve,
      cvss: (map(.cvss) | max),
      package: .[0].package,
      versions: (map(.version) | map(select(. != "")) | unique | join(", ")),
      hosts: (map(.host) | unique | join(", ")),
    })
  | sort_by(-.cvss);
{ new: grouped($newFlat), fixed: grouped($fixedFlat) }
JQ

diff_json="$(jq -n --slurpfile before "$before_flat" --slurpfile after "$after_flat" \
  -f "$WORK/diff.jq")"

new_count="$(jq '.new | length' <<<"$diff_json")"
fixed_count="$(jq '.fixed | length' <<<"$diff_json")"

echo '### Security'
echo
if [ "$new_count" -eq 0 ] && [ "$fixed_count" -eq 0 ]; then
  echo 'No CVE changes'
elif [ "$new_count" -gt 0 ] && [ "$fixed_count" -gt 0 ]; then
  echo "$fixed_count CVEs fixed, $new_count new"
elif [ "$fixed_count" -gt 0 ]; then
  echo "$fixed_count CVEs fixed"
else
  echo "$new_count new CVEs"
fi
echo

if [ "$new_count" -gt 0 ] || [ "$fixed_count" -gt 0 ]; then
  echo '<details><summary>CVE changes</summary>'
  echo
  render_table() {
    local label="$1" rows="$2"
    echo "**$label**"
    echo
    if [ -z "$rows" ]; then
      echo '_None_'
    else
      echo '| CVE | CVSS | Package | Hosts |'
      echo '| --- | --- | --- | --- |'
      echo "$rows"
    fi
    echo
  }
  pkg_col='if .versions != "" then .package + " " + .versions else .package end'
  new_rows="$(jq -r ".new[] | \"| [\(.cve)](https://nvd.nist.gov/vuln/detail/\(.cve)) | \(.cvss) | \($pkg_col) | \(.hosts) |\"" <<<"$diff_json")"
  fixed_rows="$(jq -r ".fixed[] | \"| [\(.cve)](https://nvd.nist.gov/vuln/detail/\(.cve)) | \(.cvss) | \($pkg_col) | \(.hosts) |\"" <<<"$diff_json")"
  render_table 'New' "$new_rows"
  render_table 'Fixed' "$fixed_rows"
  echo '</details>'
  echo
fi

# --- Local builds: new-vs-main cache misses per host ------------------------
# Counting every package `nix build --dry-run` would build after the update
# is mostly noise: most of it is already true on main. Instead diff the
# before/after "will be built" name sets and show only what's new.
names_in() {
  local log="$1"
  [ -f "$log" ] || return 0
  awk '
    /will be built:/ { capture=1; next }
    /will be fetched/ { capture=0 }
    capture && /^  \// { print }
  ' "$log" | sed -E 's#^  /nix/store/[^-]+-##; s#\.drv$##' | sort -u
}

echo '### Local builds'
echo
build_names=""
for host in "${HOSTS[@]}"; do
  if [ -f "$WORKDIR/build-before-$host.failed" ] || [ -f "$WORKDIR/build-after-$host.failed" ]; then
    echo "$host: local build check failed"
    continue
  fi
  before_names="$(names_in "$WORKDIR/build-before-$host.log")"
  after_names="$(names_in "$WORKDIR/build-after-$host.log")"
  new_names="$(comm -13 <(echo "$before_names") <(echo "$after_names") | sed '/^$/d')"
  total=0
  if [ -n "$after_names" ]; then total="$(wc -l <<<"$after_names")"; fi
  new_count=0
  if [ -n "$new_names" ]; then new_count="$(wc -l <<<"$new_names")"; fi
  if [ "$new_count" -eq 0 ]; then
    echo "$host: no new local builds ($total total)"
  else
    echo "$host: $new_count new local build$([ "$new_count" = 1 ] || echo s) ($total total)"
    build_names="$build_names**$host**:
- ${new_names//$'\n'/$'\n- '}

"
  fi
done
echo
if [ -n "$build_names" ]; then
  echo '<details><summary>Packages built locally</summary>'
  echo
  printf '%s' "$build_names"
  echo '</details>'
fi
