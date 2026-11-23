# {host: {new: [...], existing: [...]}} for the hosts in $hosts: the NixOS eval warnings after an
# update ($a[0].warnings) split by whether they were already there before ($b[0].warnings).
# Hosts with no warnings are dropped. Store paths and whitespace are normalised, so a warning
# that only moved to a new source path or wraps differently still counts as existing.
#   jq -n -f warnings-diff.jq --argjson hosts '[...]' --slurpfile a after.json --slurpfile b before.json
def norm: gsub("/nix/store/[a-z0-9]{32}-"; "") | gsub("\\s+"; " ") | sub(" $"; "");
$hosts
| map(
    . as $h
    | (($b[0].warnings[$h] // []) | map(norm)) as $old
    | (($a[0].warnings[$h] // []) | map(norm)) as $now
    | { key: $h, value: { new: ($now - $old), existing: ($now - ($now - $old)) } }
  )
| from_entries
| with_entries(select((.value.new + .value.existing) | length > 0))
