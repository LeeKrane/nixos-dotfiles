#   nix eval --json --impure '.#lib.hostMeta' --apply 'import ./scripts/hosts.nix'
hostMeta: builtins.filter (n: hostMeta.${n}.system == "x86_64-linux") (builtins.attrNames hostMeta)
