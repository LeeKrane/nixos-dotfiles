# Host list shared by check.yml's eval matrix and docker-check.sh: every host whose host.nix
# says x86_64-linux (the aarch64 Pis: the x86 runners cannot build them, checks.pi-eval only
# evaluates them). update.yml's reports are not restricted to it: they cover every host.
# Takes the flake's `lib.hostMeta` (flake.nix), which has no `-vm`
# check target and reads no nixpkgs, so the list lives in exactly one place.
#   nix eval --json --impure '.#lib.hostMeta' --apply 'import ./scripts/hosts.nix'
hostMeta: builtins.filter (n: hostMeta.${n}.system == "x86_64-linux") (builtins.attrNames hostMeta)
