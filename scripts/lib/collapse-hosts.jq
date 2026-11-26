# collapse_hosts($roles): host names -> one display string for PR bodies. $roles is {host: role} for every flake host (lib.hostMeta),
# so "all" means the whole flake. A complete role group shows as its role plus "s"; other hosts follow by name.
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
