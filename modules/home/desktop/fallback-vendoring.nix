# Stub for docs/FALLBACK-VENDORING.md: `krane.iiVendored.enable` does nothing today; enabling it
# fails with a documented assertion.
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
      this on fails the build with a pointer to docs/FALLBACK-VENDORING.md,
      which documents the steps by hand.
    '';
  };

  config.assertions = [
    {
      assertion = !cfg.enable;
      message = ''
        krane.iiVendored.enable is not implemented. Follow
        docs/FALLBACK-VENDORING.md to self-vendor dots-hyprland by hand, then
        remove this option (or set it back to false) once that replacement
        is in place.
      '';
    }
  ];
}
