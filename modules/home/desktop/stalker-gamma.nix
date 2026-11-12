# S.T.A.L.K.E.R. G.A.M.M.A. on the free, standalone Anomaly. Imported by
# hosts/tarmantria/default.nix and hosts/tariognatha/default.nix.
#
# gamma-launcher replaces GAMMA's Windows-only installer. The game is live state, never declared
# here: `gamma-launcher full-install --anomaly ~/Games/STALKER/ANOMALY --gamma ~/Games/STALKER/GAMMA
# --cache-directory ~/Games/STALKER/gamma-launcher-cache` downloads ~150G, with TMPDIR off a small
# /tmp. GAMMA/ModOrganizer.exe then runs as a non-Steam game under Proton, with the d3dx/vcrun2022
# winetricks set from protontricks, instance dir GAMMA and game dir ANOMALY.
{ pkgs, ... }:
{
  home.packages = [ pkgs.gamma-launcher ];
}
