#   HOSTS_JSON='["taragarmr"]' nix eval --json --impure '.#nixosConfigurations' \
#     --apply 'cfgs: import scripts/update-versions.nix cfgs (builtins.fromJSON (builtins.getEnv "HOSTS_JSON"))'
# Lookups go through attrByPath, which never throws on missing attributes or wrong shapes; tryVersion's tryEval catches throws when forcing the
# final value (e.g. a failing assertion). A renamed or removed attribute drops only that entry instead of failing the weekly update.
configs: hosts:
let
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
        # ii wraps quickshell in a symlinkJoin without .version: read the package from illogical-flake's input (as lib/mk-host.nix passes iiInputs.quickshell).
        Quickshell = attrByPath [
          "illogical-flake"
          "inputs"
          "quickshell"
          "packages"
          system
          "default"
          "version"
        ] null inputs;
        "zen-browser" = attrByPath [
          "zen-browser"
          "packages"
          system
          "default"
          "version"
        ] null inputs;
        # pkgs/default.nix overlays nixpkgs' claude-code, so this is the version pinned in pkgs/claude-code/manifest.zst.json.
        "claude-code" = attrByPath [ "pkgs" "claude-code" "version" ] null cfg;
        Mesa = attrByPath [ "pkgs" "mesa" "version" ] null cfg;
        NixOS = attrByPath [ "config" "system" "nixos" "version" ] null cfg;
      }
      # Only hosts using the NVIDIA driver (config.hardware.nvidia.enabled) report its version.
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
