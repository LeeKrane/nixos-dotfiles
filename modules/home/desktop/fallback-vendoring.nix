# Stub for self-vendoring dots-hyprland (docs/II-INTEGRATION.md, "If the soymou module breaks"):
# `krane.iiVendored.enable` does nothing today; enabling it fails with an assertion.
# An assertion, not `throw` in config: pushDownProperties forces mkIf content to WHNF regardless
# of cond, so a throw would fire on every host. An assertion's boolean is checked only when
# config.system.build.toplevel evaluates it.
{
  config,
  lib,
  ...
}:
let
  cfg = config.krane.iiVendored;
in
{
  options.krane.iiVendored.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = ''
      Placeholder for self-vendoring end-4's dots-hyprland directly instead
      of going through soymou/illogical-flake. Not implemented: flipping
      this on fails the build with a pointer to docs/II-INTEGRATION.md,
      section "If the soymou module breaks".
    '';
  };

  config.assertions = [
    {
      assertion = !cfg.enable;
      message = ''
        krane.iiVendored.enable is a stub; see docs/II-INTEGRATION.md, section
        "If the soymou module breaks", for the self-vendoring approach.
      '';
    }
  ];
}
