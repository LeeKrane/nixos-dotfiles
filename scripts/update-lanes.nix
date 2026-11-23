# Weekly update lanes (docs/superpowers/specs/2026-11-23-update-lanes-design.md). Takes the
# parsed flake.lock and returns { servers = [ input ]; desktops = [ input ]; }:
#   nix eval --json --impure --expr 'import ./scripts/update-lanes.nix (builtins.fromJSON (builtins.readFile ./flake.lock))'
# servers: the stable channel (nixpkgs-stable moves with nixos-raspberrypi through its follows)
# plus the inputs both roles use. desktops: every other updatable root input, so a new input
# lands there by default. A `follows` root input (a list in flake.lock) is in neither lane: it
# moves with the input it follows.
lock:
let
  rootInputs = lock.nodes.${lock.root}.inputs;
  updatable = builtins.filter (n: builtins.isString rootInputs.${n}) (builtins.attrNames rootInputs);
  servers = [
    "nixos-raspberrypi"
    "home-manager-stable"
    "nixvim-stable"
    "sops-nix"
    "disko"
    "nix-index-database"
  ];
  unknown = builtins.filter (n: !(builtins.elem n updatable)) servers;
in
if unknown != [ ] then
  throw "update-lanes.nix: server-lane inputs not updatable root inputs of flake.lock: ${toString unknown}"
else
  {
    inherit servers;
    desktops = builtins.filter (n: !(builtins.elem n servers)) updatable;
  }
