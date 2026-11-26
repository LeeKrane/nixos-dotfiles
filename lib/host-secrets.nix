# Per-host secrets file lookup. `hostName` is the mk-host.nix specialArg, not `config.networking.hostName`:
# tariognatha-vm overrides the latter but shares tariognatha's secrets file.
{ lib, hostName }:
let
  # A Nix path, not a string, so `builtins.pathExists`/`sopsFile` get the
  # real store path.
  file = ../secrets/${hostName}.yaml;
  exists = builtins.pathExists file;

  # sops encrypts values, not key names, so top-level sections are readable at eval time; an absent
  # section means the feature is off on this host.
  lines = lib.optionals exists (lib.splitString "\n" (builtins.readFile file));
in
{
  inherit file exists;
  hasSection =
    name:
    lib.any (p: lib.any (lib.hasPrefix p) lines) [
      "${name}:"
      "\"${name}\":"
      "'${name}':"
    ];
}
