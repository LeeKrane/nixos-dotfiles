{
  lib,
  writeShellApplication,
  curl,
  jq,
  gawk,
  gnused,
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
    gnused
    libnotify
    xdg-utils
    coreutils
    systemd
  ];

  # Drops the shebang; writeShellApplication adds its own.
  text = lib.concatStringsSep "\n" (
    lib.tail (lib.splitString "\n" (builtins.readFile ../../scripts/flake-update-notify.sh))
  );

  meta.mainProgram = "flake-update-notify";
}
