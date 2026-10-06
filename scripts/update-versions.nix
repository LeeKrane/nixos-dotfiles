# Evaluated against the flake's nixosConfigurations attrset (not a single host) to print
# the package versions update.yml shows in the weekly update PR body
# (scripts/update-summary.sh), for the hosts update.yml passes in. Called once before
# `nix flake update` and once after, with the shared host list (update.yml computes it
# once from `nixosConfigurations`'s attribute names, excluding the `-vm` check target)
# curried in ahead of the `configs` attrset `--apply` itself provides:
#   nix eval --json --impure '.#nixosConfigurations' \
#     --apply 'import scripts/update-versions.nix [ "taractias" "tariognatha" "tarmantria" ]'
#
# Every lookup goes through attrByPath, which walks a path of attribute names through
# nested sets using `?`/`or` and returns `default` the moment an attribute is missing, a
# dynamic segment (e.g. `system`) isn't a string, or an intermediate value isn't an
# attrset at all — never throwing. That alone isn't quite enough: forcing the value found
# at the end of the path can still throw (an assertion failing somewhere inside a
# derivation, say), and unlike missing-attribute or type errors, that kind of throw *is*
# catchable, so tryVersion wraps the final result in tryEval as a second line of defense.
# Either way, a renamed or removed attribute (a nixpkgs restructuring, illogical-flake
# dropping an input, ...) drops just that one entry for that host instead of failing the
# whole weekly update run.
hosts: configs:
let
  # attrByPath PATH DEFAULT SET: walks PATH (a list of attribute names, static or
  # dynamic) through nested attrsets, returning DEFAULT as soon as a segment is missing,
  # isn't a string (a dynamic segment computed as null, say), or the value to descend
  # into isn't an attrset. `?` and `or` never throw on their own, so this function never
  # throws regardless of how wrong the shapes it's given are.
  attrByPath =
    path: default: set:
    let
      walk =
        remaining: value:
        if remaining == [ ] then
          value
        else
          let
            key = builtins.head remaining;
          in
          if !(builtins.isString key) then
            default
          else if value ? ${key} then
            walk (builtins.tail remaining) value.${key}
          else
            default;
    in
    walk path set;

  tryVersion =
    expr:
    let
      result = builtins.tryEval (builtins.deepSeq expr expr);
    in
    if result.success then result.value else null;

  # home-manager packages (claude-code, zen-browser) and system packages (hyprland,
  # mesa, the nvidia driver, the kernel) are read from very different places, so each
  # entry below picks whichever of config/pkgs/specialArgs actually carries it.
  versionsFor =
    cfg:
    let
      system = attrByPath [ "pkgs" "stdenv" "hostPlatform" "system" ] null cfg;
      inputs = attrByPath [ "_module" "specialArgs" "inputs" ] { } cfg;
      nvidiaUsed =
        let
          r = builtins.tryEval (attrByPath [ "config" "hardware" "nvidia" "enabled" ] false cfg);
        in
        r.success && r.value == true;
    in
    builtins.mapAttrs (_: tryVersion) (
      {
        "Linux kernel" = attrByPath [ "config" "boot" "kernelPackages" "kernel" "version" ] null cfg;
        Hyprland = attrByPath [ "config" "programs" "hyprland" "package" "version" ] null cfg;
        # ii wraps quickshell in a symlinkJoin with no .version of its own, so read the
        # underlying package straight off illogical-flake's own input instead (the same
        # input lib/mk-host.nix hands to the patched home-module.nix as iiInputs.quickshell).
        Quickshell = attrByPath [
          "illogical-flake"
          "inputs"
          "quickshell"
          "packages"
          system
          "default"
          "version"
        ] null inputs;
        # Same flake-input route as apps.nix's home.packages entry
        # (inputs.zen-browser.packages.${system}.default).
        "zen-browser" = attrByPath [
          "zen-browser"
          "packages"
          system
          "default"
          "version"
        ] null inputs;
        # pkgs/default.nix overlays nixpkgs' claude-code with the vendored package, so this is
        # the version pkgs/claude-code/manifest.zst.json pins, not the nixpkgs one.
        "claude-code" = attrByPath [ "pkgs" "claude-code" "version" ] null cfg;
        Mesa = attrByPath [ "pkgs" "mesa" "version" ] null cfg;
        NixOS = attrByPath [ "config" "system" "nixos" "version" ] null cfg;
      }
      # Report the NVIDIA driver version only for hosts that actually use it
      # (config.hardware.nvidia.enabled), omitting the entry entirely elsewhere rather
      # than showing a perpetual "- -" row for hosts with no NVIDIA GPU.
      // (
        if nvidiaUsed then
          {
            "NVIDIA driver" = attrByPath [ "config" "hardware" "nvidia" "package" "version" ] null cfg;
          }
        else
          { }
      )
    );
in
builtins.listToAttrs (
  map (host: {
    name = host;
    value = versionsFor configs.${host};
  }) hosts
)
