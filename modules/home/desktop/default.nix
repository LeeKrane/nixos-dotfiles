# tarkov.nix, spt.nix, stalker-gamma.nix and heuristiclab.nix are imported per host only.
{ ... }:
{
  imports = [
    ./hypr-config.nix
    ./illogical-impulse.nix
    ./ii-config-dir.nix
    ./ii-settings.nix
    ./cli.nix
    ./neovim.nix
    ./dev.nix
    ./apps.nix
    ./proton-drive.nix
    ./fallback-vendoring.nix
    ./wallpapers.nix
    ./lock-on-start.nix
    ./cursor.nix
    ./session-target.nix
    ./qwertz-binds.nix
    ./recording.nix
    ./drawing.nix
    ./flake-update-notify.nix
    ./server-upgrade-notify.nix
    ./steam.nix
    ./ani-cli.nix
  ];
}
