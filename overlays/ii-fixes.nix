# Fixes for nixpkgs changes soymou's illogical-flake hasn't caught up with.
final: prev: {
  # soymou still references gnome-icon-theme, which nixpkgs dropped.
  gnome-icon-theme = prev.adwaita-icon-theme;

  # soymou reads kde-material-you-colors from the python package set; nixpkgs moved it to pkgs/by-name.
  pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
    (_pyFinal: pyPrev: {
      kde-material-you-colors = pyPrev.kde-material-you-colors or final.kde-material-you-colors;
    })
  ];
}
