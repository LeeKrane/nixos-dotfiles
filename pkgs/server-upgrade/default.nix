# server-upgrade-hooks (systemd hooks) and server-upgrade-report (GitHub issues).
# The nixos-upgrade unit's own PATH supplies nix-env.
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
  # Drops the shebang; writeShellApplication adds its own.
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
