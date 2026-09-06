# Escape hatch stub for docs/FALLBACK-VENDORING.md. `krane.iiVendored.enable`
# does nothing today. It exists so the day soymou/illogical-flake goes stale,
# flipping it on gives a documented, discoverable failure rather than a
# silent no-op or a mystery eval error somewhere else.
#
# Why an assertion, not `throw` in config directly: `mkIf cond (throw "...")` looks lazy but
# isn't. pushDownProperties inspects `content` to decide whether to push mkIf into nested
# attrsets, which forces it to WHNF regardless of `cond`, so the throw fires on every host
# unconditionally. An `assertions` entry avoids this: its `assertion` field is a plain boolean,
# never forced to exist, and is checked only when config.system.build.toplevel evaluates it.
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
