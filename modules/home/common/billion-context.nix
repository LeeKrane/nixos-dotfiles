# billion-context (`bili`) and its config, used by the `claude` fish function in
# modules/nixos/common/claude.nix. ~/.config/billion-context is not in ii's wipe set.
{ pkgs, lib, ... }:
let
  config = {
    compress = {
      # Hard cap: the window bili budgets against, even if the model declares more.
      modelContextLimit = 400000;
      # Forced compression above 75% of 400K, the 300K soft target.
      maxContextLimit = "75%";
      # Emergency compression above 95%, last resort before the hard cap.
      emergencyThresholdPercent = "95%";
      # Few but deep compressions: wait for 300K of growth between nudges, and skip a
      # compression that would free less than 150K.
      nudgeGrowthTokens = 300000;
      minPressureBenefitTokens = 150000;
      # Only compress when the model was nudged, never unprompted.
      requireNudge = true;
    };
    # cacheKeepalive deliberately absent: no synthetic cache pings.
  };
  configFile = pkgs.writeText "billion-context.json" (builtins.toJSON config);
in
{
  home.packages = [ pkgs.billion-context ];

  # Copied, not a home.file symlink: the bili Web UI writes its settings (proxy, ...) to this
  # file, and a read-only store symlink would break that. Each activation resets it to the
  # declared values, so UI edits last until the next switch. Config path and plain-JSON
  # format per the package's docs/configuration.md.
  home.activation.billionContextConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -Dm644 ${configFile} "$HOME/.config/billion-context/billion-context.json"
  '';
}
