# Fixes for nixpkgs changes soymou's illogical-flake hasn't caught up with.
final: prev: {
  # nixpkgs dropped gnome-icon-theme. soymou still references it.
  gnome-icon-theme = prev.adwaita-icon-theme;

  # nixpkgs moved kde-material-you-colors from python3Packages to pkgs/by-name.
  # soymou still reads it from the python package set (ps."kde-material-you-colors").
  pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
    (_pyFinal: pyPrev: {
      kde-material-you-colors = pyPrev.kde-material-you-colors or final.kde-material-you-colors;
    })
  ];

  # kde-material-you-colors' python-magic crash, fixed upstream (nixpkgs PR #490280, v2.2.0). Ready if it regresses:
  # kde-material-you-colors = prev.kde-material-you-colors.overridePythonAttrs (old: { ... });
}
