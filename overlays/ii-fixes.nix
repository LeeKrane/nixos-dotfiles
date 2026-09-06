# Fixes for nixpkgs changes soymou's illogical-flake hasn't caught up with.
_final: prev: {
  # nixpkgs dropped gnome-icon-theme. soymou still references it.
  gnome-icon-theme = prev.adwaita-icon-theme;

  # kde-material-you-colors' python-magic crash, fixed upstream (nixpkgs PR #490280, v2.2.0). Ready if it regresses:
  # kde-material-you-colors = prev.kde-material-you-colors.overridePythonAttrs (old: { ... });
}
