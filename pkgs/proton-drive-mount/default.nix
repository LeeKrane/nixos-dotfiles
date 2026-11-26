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

  # The script handles rclone failures itself (retry, 2FA prompts); errexit would abort them.
  bashOptions = [ ];

  # SC2034: only `$?` of `yad_response=$(yad ...)` is used.
  excludeShellChecks = [ "SC2034" ];

  # Drops the shebang; writeShellApplication adds its own.
  text = lib.concatStringsSep "\n" (
    lib.tail (lib.splitString "\n" (builtins.readFile ../../scripts/proton-drive-rclone-mount.sh))
  );

  meta.mainProgram = "proton-drive-mount";
}
