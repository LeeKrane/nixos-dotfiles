#   nix eval --json --impure --expr 'import ./scripts/update-lanes.nix (builtins.fromJSON (builtins.readFile ./flake.lock))'
# servers: the stable channel plus the inputs both roles use. desktops: every other updatable root input.
# A `follows` root input (a list in flake.lock) is in neither lane.
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
