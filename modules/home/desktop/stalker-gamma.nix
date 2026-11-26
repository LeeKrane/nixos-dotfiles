# S.T.A.L.K.E.R. G.A.M.M.A. on standalone Anomaly. gamma-launcher replaces GAMMA's Windows-only
# installer; the game is live state: `gamma-launcher full-install --anomaly ~/Games/STALKER/ANOMALY
# --gamma ~/Games/STALKER/GAMMA --cache-directory ~/Games/STALKER/gamma-launcher-cache` (~150G,
# TMPDIR off a small /tmp). Then run GAMMA/ModOrganizer.exe as a non-Steam game under Proton with
# the d3dx/vcrun2022 winetricks set from protontricks.
{ pkgs, ... }:
{
  home.packages = [ pkgs.gamma-launcher ];
}
