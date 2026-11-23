# collapse_hosts($roles): an array of host names -> one display string for PR bodies
# (docs/superpowers/specs/2026-11-23-update-lanes-design.md, "Host list collapsing").
# $roles is {host: role} for EVERY host of the flake (lib.hostMeta), so "all" means the whole
# flake, not the hosts a lane touched. A complete role group shows as its role plus "s"
# ("servers", "desktops"); hosts outside a complete group follow by name, in input order.
def collapse_hosts($roles):
  . as $hs
  | ($roles | keys) as $all
  | if ($hs | length) == 0 then ""
    elif ($all - $hs | length) == 0 then "all"
    else
      ([$roles[]] | unique) as $roleNames
      | [ $roleNames[] as $r
          | [$roles | to_entries[] | select(.value == $r) | .key] as $members
          | select(($members - $hs | length) == 0)
          | { name: ($r + "s"), members: $members } ] as $full
      | [$full[].members[]] as $covered
      | ([$full[].name] + [$hs[] | select((. as $h | $covered | any(.[]; . == $h)) | not)])
      | join(", ")
    end;
