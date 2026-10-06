# Host list shared by check.yml's eval matrix and update.yml's update and
# security jobs: every nixosConfigurations attribute except the `-vm` check
# target (flake.nix), so the list lives in exactly one place.
#   nix eval --json --impure '.#nixosConfigurations' --apply 'import ./scripts/hosts.nix'
cfgs: builtins.filter (n: builtins.match ".*-vm" n == null) (builtins.attrNames cfgs)
