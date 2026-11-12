# Home-manager modules for role "desktop" (Hyprland + illogical-impulse). tarkov.nix, spt.nix,
# stalker-gamma.nix and heuristiclab.nix are not listed: only the hosts that use them import
# them (see hosts/tariognatha/default.nix).
{ ... }:
{
  imports = [
    ./hypr-config.nix
    ./illogical-impulse.nix
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
    ./teamclaude.nix
    ./flake-update-notify.nix
    ./steam.nix
  ];
}
