# taragarmr: AZW SER mini PC (Ryzen 7 6800H), role server. Home server: WireGuard hub, public
# ingress, SPT/Fika, CouchDB, teamclaude, restic backups. LAN address 192.168.178.23 (DHCP lease
# pinned in the Fritzbox).
#
# First install:
#   nix run github:nix-community/nixos-anywhere -- --flake .#taragarmr \
#     --generate-hardware-config nixos-generate-config ./hosts/taragarmr/hardware-configuration.nix \
#     --target-host root@<installer-ip>
# The sops age key derives from this host's SSH host key, pre-generated and stored encrypted in
# the password manager (age recipient &host_taragarmr in .sops.yaml); restore it to
# <dir>/etc/ssh/ and inject it with `nixos-anywhere ... --extra-files <dir>` so
# secrets/taragarmr.yaml decrypts on first boot.
# krane's password is not in the repo or sops; set it on site: add `--phases kexec,disko,install` (skips the reboot phase) to the
# nixos-anywhere call above (same command, same --extra-files), then
#   ssh root@<installer-ip> nixos-enter --root /mnt -c 'passwd krane'    (interactive)
# and reboot the installer. Without it sudo is unusable and deploys fail. Later deploys:
#   nixos-rebuild switch --flake .#taragarmr --target-host krane@taragarmr --sudo --ask-sudo-password
#
# Secrets (secrets/taragarmr.yaml): wireguard/{wg0,wg1}-private-key, couchdb/env,
# restic/repo-password, server-upgrade/github-token, ntfy/{publish-token,server-env}. A missing
# section switches that feature off.
{ ... }:
{
  imports = [
    ./hardware-configuration.nix
    ./disko.nix
    ./caddy.nix
    ./ntfy.nix
    ./couchdb.nix
    ./spt.nix
    ./services.nix
    ./backup.nix
    ./backup-drive.nix
  ];

  system.stateVersion = "26.05";

  # One host per hour: the Pis first, the WireGuard hub last.
  krane.autoUpgrade.rebootWindow = {
    lower = "04:59";
    upper = "06:00";
  };

  boot.loader.systemd-boot = {
    enable = true;
    # The ESP holds every generation's kernel and initrd.
    configurationLimit = 10;
  };
  boot.loader.efi.canTouchEfiVariables = true;
}
