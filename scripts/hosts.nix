# Host list shared by check.yml's eval matrix and update.yml's update and
# security jobs: every nixosConfigurations attribute except the `-vm` check
# target (flake.nix) and hosts that are not x86_64-linux (aarch64 Pis: the x86 runners
# cannot build or scan them), so the list lives in exactly one place.
#   nix eval --json --impure '.#nixosConfigurations' --apply 'import ./scripts/hosts.nix'
cfgs:
builtins.filter (
  n: builtins.match ".*-vm" n == null && cfgs.${n}.pkgs.stdenv.hostPlatform.system == "x86_64-linux"
) (builtins.attrNames cfgs)
