#   nix eval --json --impure '.#nixosConfigurations' --apply 'cfgs: import ./scripts/host-warnings.nix cfgs [ "taragarmr" ]'
cfgs: hosts:
builtins.listToAttrs (
  map (h: {
    name = h;
    value = cfgs.${h}.config.warnings;
  }) hosts
)
