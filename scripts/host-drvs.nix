# { host = toplevel drvPath; } for the given hosts, from the flake's nixosConfigurations. Shared
# by update-lane.yml's changed-host eval and its security job, so both look at the same drvs.
#   nix eval --json --impure '.#nixosConfigurations' --apply 'cfgs: import ./scripts/host-drvs.nix cfgs [ "taragarmr" ]'
cfgs: hosts:
builtins.listToAttrs (
  map (h: {
    name = h;
    value = cfgs.${h}.config.system.build.toplevel.drvPath;
  }) hosts
)
