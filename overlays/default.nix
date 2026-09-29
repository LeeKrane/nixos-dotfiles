# Overlays for every host's pkgs, exposed as `overlays.default`.
[
  (import ./ii-fixes.nix)
  (import ./ani-cli.nix)
  (import ./dolphin-darkly-selection.nix)
  (import ./gsr-ui-fractional-scale.nix)
  # Exposes pkgs/ as top-level packages, so boot.nix can use pkgs.plymouth-lone.
  (final: _prev: import ../pkgs { pkgs = final; })
]
