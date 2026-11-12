# Per-host secrets file lookup shared by modules that gate sops declarations on it.
# `hostName` is the mk-host.nix specialArg, not `config.networking.hostName`:
# tariognatha-vm overrides the latter but shares tariognatha's secrets file.
{ lib, hostName }:
let
  # A Nix path, not a string, so `builtins.pathExists`/`sopsFile` get the
  # real store path.
  file = ../secrets/${hostName}.yaml;
  exists = builtins.pathExists file;

  # sops encrypts values, not key names, so the top-level sections are readable at eval time.
  # A section absent from the file means that feature is off on this host; an empty value
  # cannot be detected (it is encrypted like any other).
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
