#   nix eval --json --impure '.#nixosConfigurations' --apply 'cfgs: import ./scripts/host-drvs.nix cfgs [ "taragarmr" ]'
cfgs: hosts:
builtins.listToAttrs (
  map (h: {
    name = h;
    value = cfgs.${h}.config.system.build.toplevel.drvPath;
  }) hosts
)
