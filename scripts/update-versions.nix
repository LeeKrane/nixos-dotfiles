# Evaluated against the flake's nixosConfigurations attrset (not a single host) to print
# the package versions update.yml shows in the weekly update PR body
# (scripts/update-summary.sh), for every real host — tariognatha-vm is a check target, not
# one of hosts/, so it's left out. Called once before `nix flake update` and once after:
#   nix eval --json --impure '.#nixosConfigurations' --apply 'import scripts/update-versions.nix'
# Each lookup is wrapped in tryEval, so a renamed or removed attribute (a nixpkgs
# restructuring, illogical-flake dropping an input, ...) drops just that one entry for that
# host instead of failing the whole weekly update run.
configs:
let
  hosts = [
    "taractias"
    "tariognatha"
    "tarmantria"
  ];

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
      inherit (cfg) config pkgs;
      inputs = cfg._module.specialArgs.inputs;
      system = pkgs.stdenv.hostPlatform.system;
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
    };
in
builtins.listToAttrs (
  map (host: {
    name = host;
    value = versionsFor configs.${host};
  }) hosts
)
