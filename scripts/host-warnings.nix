# { host = config.warnings; } for the given hosts, from the flake's nixosConfigurations. Used by
# update-lane.yml's changed-host eval. A warning that throws gives that host [] (tryEval catches
# only throw/assert; other eval errors would already fail the host's toplevel drv).
#   nix eval --json --impure '.#nixosConfigurations' --apply 'cfgs: import ./scripts/host-warnings.nix cfgs [ "taragarmr" ]'
cfgs: hosts:
builtins.listToAttrs (
  map (h: {
    name = h;
    value =
      let
        w = cfgs.${h}.config.warnings;
        r = builtins.tryEval (builtins.deepSeq w w);
      in
      if r.success then r.value else [ ];
  }) hosts
)
