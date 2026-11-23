# The two scripts of the automatic server upgrade as one package (the flake-update-notify
# pattern, so they are built and shellchecked on their own): server-upgrade-hooks (systemd
# hooks, scripts/server-upgrade-hooks.sh) and server-upgrade-report (GitHub issues,
# scripts/server-upgrade-report.sh). The nixos-upgrade unit's own PATH supplies nix-env.
{
  lib,
  writeShellApplication,
  symlinkJoin,
  gitMinimal,
  jq,
  curl,
  gawk,
  coreutils,
  systemd,
}:
let
  # Strips the original `#!/usr/bin/env bash` line. writeShellApplication adds its own.
  script =
    name: runtimeInputs:
    writeShellApplication {
      inherit name runtimeInputs;
      text = lib.concatStringsSep "\n" (
        lib.tail (lib.splitString "\n" (builtins.readFile ../../scripts/${name}.sh))
      );
      meta.mainProgram = name;
    };
  report = script "server-upgrade-report" [
    curl
    jq
  ];
  hooks = script "server-upgrade-hooks" [
    gitMinimal
    jq
    curl
    gawk
    coreutils
    systemd
    report
  ];
in
symlinkJoin {
  name = "server-upgrade";
  paths = [
    hooks
    report
  ];
}
