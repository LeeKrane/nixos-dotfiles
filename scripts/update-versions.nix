# Evaluated against a nixosConfigurations.<host> value (not the flake itself) to print
# the package versions update.yml shows in the weekly update PR body
# (scripts/update-summary.sh). Called once before `nix flake update` and once after, host
# fixed to tarmantria:
#   nix eval --json '.#nixosConfigurations.tarmantria' --apply 'import scripts/update-versions.nix'
# Each lookup is wrapped in tryEval, so a renamed or removed attribute (a nixpkgs
# restructuring, illogical-flake dropping an input, ...) drops just that one entry instead
# of failing the whole weekly update run.
cfg:
let
  inherit (cfg) config pkgs;
  # home-manager packages (claude-code, zen-browser) and system packages (hyprland,
  # mesa, the nvidia driver, the kernel) are read from very different places, so each
  # entry below picks whichever of config/pkgs/specialArgs actually carries it.
  inputs = cfg._module.specialArgs.inputs;
  system = pkgs.stdenv.hostPlatform.system;

  tryVersion =
    expr:
    let
      result = builtins.tryEval (builtins.deepSeq expr expr);
    in
    if result.success then result.value else null;
in
builtins.mapAttrs (_: tryVersion) {
  "Linux kernel" = config.boot.kernelPackages.kernel.version;
  Hyprland = config.programs.hyprland.package.version;
  # ii wraps quickshell in a symlinkJoin with no .version of its own, so read the
  # underlying package straight off illogical-flake's own input instead (the same
  # input lib/mk-host.nix hands to the patched home-module.nix as iiInputs.quickshell).
  Quickshell = inputs.illogical-flake.inputs.quickshell.packages.${system}.default.version;
  # Same flake-input route as apps.nix's home.packages entry
  # (inputs.zen-browser.packages.${system}.default).
  "zen-browser" = inputs.zen-browser.packages.${system}.default.version;
  # pkgs/default.nix overlays nixpkgs' claude-code with the vendored package, so this is
  # the version pkgs/claude-code/manifest.zst.json pins, not the nixpkgs one.
  "claude-code" = pkgs.claude-code.version;
  Mesa = pkgs.mesa.version;
  "NVIDIA driver" = config.hardware.nvidia.package.version;
  NixOS = config.system.nixos.version;
}
