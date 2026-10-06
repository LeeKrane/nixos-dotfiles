# Wraps scripts/flake-update-notify.sh as a package, so it can be built and
# shellchecked on its own.
{
  lib,
  writeShellApplication,
  curl,
  jq,
  gawk,
  libnotify,
  xdg-utils,
  coreutils,
  systemd,
}:
writeShellApplication {
  name = "flake-update-notify";
  runtimeInputs = [
    curl
    jq
    gawk
    libnotify
    xdg-utils
    coreutils
    systemd
  ];

  # Strips the original `#!/usr/bin/env bash` line. writeShellApplication adds
  # its own ahead of `text`.
  text = lib.concatStringsSep "\n" (
    lib.tail (lib.splitString "\n" (builtins.readFile ../../scripts/flake-update-notify.sh))
  );

  meta.mainProgram = "flake-update-notify";
}
