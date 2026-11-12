# taronychus: Raspberry Pi 5 (8 GB), boots from a 1 TB NVMe (Lexar NM710). Primary backup
# target (restic REST server, append-only, /srv/restic) and home of gym-league.
#
# First install (no image of this host exists, the NVMe is formatted by disko):
#   1. Build and flash the nixos-raspberrypi installer to an SD card:
#        nix build .#image-installer-rpi5   (nixos-raspberrypi's installer, cached)
#      then `zstd -d` the result and dd it to the card.
#      Boot it, note its IP, and put your SSH key in (the installer takes keys from its image).
#   2. From a desktop (aarch64 closure from nixos-raspberrypi's cache):
#        nix run github:nix-community/nixos-anywhere -- --flake .#taronychus \
#          --target-host root@<installer-ip>
#      disko partitions the NVMe per ./disko.nix. The sops age key derives from the SSH host
#      key nixos-anywhere generates; add it with scripts/bootstrap-sops.sh before step 8.
#   3. Check the EEPROM boot order prefers NVMe: `rpi-eeprom-config | grep BOOT_ORDER`
#      (0xf416 = SD, then NVMe, then USB; remove the SD card after installing).
# Later deploys: nixos-rebuild switch --flake .#taronychus --target-host krane@taronychus
#
# Secrets (secrets/taronychus.yaml): wireguard/wg0-private-key, restic/htpasswd,
# restic/repo-password-taragarmr, gymleague/env. A section absent from the file switches that
# feature off, so the config evaluates before the file exists.
{
  config,
  lib,
  hostName,
  ...
}:
let
  hostSecrets = import ../../lib/host-secrets.nix { inherit lib hostName; };
  hasRestic = hostSecrets.hasSection "restic";
in
{
  imports = [
    ./disko.nix
    ./restic-prune.nix
    ./gymleague.nix
  ];

  system.stateVersion = "26.05";

  # Pi 5: the generational "kernel" bootloader (U-Boot cannot boot from NVMe/USB on a Pi 5).
  # Firmware, kernels and initrds sit on /boot/firmware (disko.nix). No other bootloader is
  # enabled: servers import no systemd-boot or grub config, checks.pi-eval asserts it.
  boot.loader.raspberry-pi.bootloader = "kernel";

  # Repository host for restic clients (taragarmr now, later others), reached over wg0 only.
  # appendOnly: a compromised client cannot delete its backups. Pruning happens here, in
  # restic-prune.nix, and the clients run with krane.backup.pruneOpts = [ ].
  krane.backupServer = {
    enable = true;
    dataDir = "/srv/restic";
    appendOnly = true;
    htpasswdFile = lib.mkIf hasRestic config.sops.secrets."restic/htpasswd".path;
  };
  sops.secrets."restic/htpasswd" = lib.mkIf hasRestic {
    owner = "restic";
    mode = "0400";
  };
  warnings =
    lib.optional (!hasRestic)
      "taronychus: secrets/taronychus.yaml has no restic section; the REST server runs without authentication and pruning is off";

  # Firewall (explicit, nothing added here): ssh (server module), wg0 (restic REST port, krane.backupServer) and the gym-league
  # backend port, which docker publishes and gymleague.nix restricts to taragarmr in the
  # DOCKER-USER chain. Nothing else is open; the old Traefik dashboard and Coolify's 80/443 do
  # not carry over, and the NixOS firewall itself opens no other port.
}
