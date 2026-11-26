#!/usr/bin/env bash
# Usage: security-summary.sh WORKDIR HOST...
#   WORKDIR per HOST: vulnix-{before,after}-<host>.json, build-{before,after}-<host>.log (raw `nix build --dry-run`),
#     build-{before,after}-<host>.failed (present if that dry-run itself failed)
#   HOST_ROLES  optional env, {host: role} JSON for every flake host: collapses host lists
set -euo pipefail
LIB="$(dirname "$(readlink -f "$0")")/lib"

WORKDIR="${1:?usage: security-summary.sh WORKDIR HOST...}"
shift
HOSTS=("$@")
if [ "${#HOSTS[@]}" -eq 0 ]; then
  echo "usage: security-summary.sh WORKDIR HOST..." >&2
  exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Flatten each host's vulnix run
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

# Diff
# Keyed on (host, cve, package), not version: a version bump that leaves the same CVE unfixed must show as neither new nor fixed.
cat >"$WORK/diff.jq" <<'JQ'
include "collapse-hosts";
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
# With HOST_ROLES, hosts collapse against the whole flake; without it, a group spanning every scanned host shows "all".
def grouped($flat):
  $flat
  | group_by([.cve, .package])
  | map({
      cve: .[0].cve,
      cvss: (map(.cvss) | max),
      package: .[0].package,
      versions: (map(.version) | map(select(. != "")) | unique | join(", ")),
      hosts: (map(.host) | unique
        | if $roles != null then collapse_hosts($roles)
          elif length == $nhosts then "all" else join(", ") end),
    })
  | sort_by(-.cvss);
{ new: grouped($newFlat), fixed: grouped($fixedFlat) }
JQ

diff_json="$(jq -n --slurpfile before "$before_flat" --slurpfile after "$after_flat" \
  -L "$LIB" --argjson roles "${HOST_ROLES:-null}" \
  --argjson nhosts "${#HOSTS[@]}" -f "$WORK/diff.jq")"

new_count="$(jq '.new | length' <<<"$diff_json")"
fixed_count="$(jq '.fixed | length' <<<"$diff_json")"

echo '### Security'
echo
if [ "$new_count" -eq 0 ] && [ "$fixed_count" -eq 0 ]; then
  echo 'No CVE changes'
elif [ "$new_count" -gt 0 ] && [ "$fixed_count" -gt 0 ]; then
  echo "$fixed_count CVE$([ "$fixed_count" = 1 ] || echo s) fixed, $new_count new"
elif [ "$fixed_count" -gt 0 ]; then
  echo "$fixed_count CVE$([ "$fixed_count" = 1 ] || echo s) fixed"
else
  echo "$new_count new CVE$([ "$new_count" = 1 ] || echo s)"
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

# Local builds
# Diff the before/after "will be built" sets and show only what is new: most of the dry-run is already true on main.
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
for host in "${HOSTS[@]}"; do
  if [ -f "$WORKDIR/build-before-$host.failed" ] || [ -f "$WORKDIR/build-after-$host.failed" ] \
    || [ ! -f "$WORKDIR/build-before-$host.log" ] || [ ! -f "$WORKDIR/build-after-$host.log" ]; then
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
  fi
done
