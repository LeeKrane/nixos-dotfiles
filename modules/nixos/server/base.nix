# Headless-server defaults: nix housekeeping, trimmed documentation, journal cap.
# trusted-users (krane, needed so `nixos-rebuild --target-host` can copy closures in) and
# auto-optimise-store come from modules/nixos/common/nix-settings.nix, the time zone from
# common/locale.nix.
#
# Deploy from a desktop (sudo keeps its password; there is no passwordless sudo):
#   nixos-rebuild switch --flake .#<host> --target-host krane@<host> --sudo --ask-sudo-password
# `--sudo --ask-sudo-password` work on both nixos-rebuild-ng generations: the stable 26.05
# one, and unstable's, where they are aliases for `--elevate=sudo --ask-elevate-password`.
{ lib, ... }:
{
  # Servers keep fewer generations around than desktops (common: 30d).
  nix.gc.options = lib.mkForce "--delete-older-than 14d";

  documentation = {
    enable = true;
    man.enable = true;
    doc.enable = false;
    info.enable = false;
    nixos.enable = false;
  };

  boot.tmp.cleanOnBoot = true;

  services.journald.extraConfig = ''
    SystemMaxUse=500M
    MaxRetentionSec=1month
  '';

  # Weekly TRIM for the SSD/NVMe hosts (a no-op where the filesystem lacks discard support).
  services.fstrim.enable = true;
}
