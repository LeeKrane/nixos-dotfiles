# { host = config.warnings; } for the given hosts, from the flake's nixosConfigurations. Used by
# update-lane.yml's changed-host eval. The same eval's toplevel drvPath already forces
# config.warnings, so a throwing warning fails the host there, not here.
#   nix eval --json --impure '.#nixosConfigurations' --apply 'cfgs: import ./scripts/host-warnings.nix cfgs [ "taragarmr" ]'
cfgs: hosts:
builtins.listToAttrs (
  map (h: {
    name = h;
    value = cfgs.${h}.config.warnings;
  }) hosts
)
