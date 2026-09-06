# Wraps scripts/proton-drive-rclone-mount.sh as a package, so it can be
# built and shellchecked on its own.
{
  lib,
  writeShellApplication,
  rclone,
  yad,
  libnotify,
  gnugrep,
  gnused,
  coreutils,
}:
writeShellApplication {
  name = "proton-drive-mount";
  runtimeInputs = [
    rclone
    yad
    libnotify
    gnugrep
    gnused
    coreutils
  ];

  # The script handles rclone's own errors via retry/2FA prompts, so
  # `set -euo pipefail` from bashOptions would abort too early.
  bashOptions = [ ];

  # SC2034: `yad_response=$(yad ...)` is unused on purpose. Only `$?`
  # decides Retry vs Cancel. Control flow here must not change.
  excludeShellChecks = [ "SC2034" ];

  # Strips the original `#!/bin/bash` line. writeShellApplication adds
  # its own ahead of `text`.
  text = lib.concatStringsSep "\n" (
    lib.tail (lib.splitString "\n" (builtins.readFile ../../scripts/proton-drive-rclone-mount.sh))
  );

  meta.mainProgram = "proton-drive-mount";
}
