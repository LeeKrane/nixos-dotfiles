# taragarmr: AZW SER mini PC (Ryzen 7 6800H, 27 GiB RAM, 512 GB NVMe), role server. The home
# server: WireGuard hub (modules/nixos/server/wireguard.nix, from lib/wireguard.nix), public
# ingress (the router forwards 80/443 here), SPT/Fika, CouchDB, teamclaude. LAN address
# 192.168.178.23 (DHCP lease pinned in the Fritzbox).
#
# First install (replaces the Fedora/Nobara host; back up per ~/server-migration first):
#   nix run github:nix-community/nixos-anywhere -- --flake .#taragarmr \
#     --generate-hardware-config nixos-generate-config ./hosts/taragarmr/hardware-configuration.nix \
#     --target-host root@<installer-ip>
# disko partitions the NVMe per ./disko.nix. The sops age key derives from this host's SSH
# host key, pre-generated in ~/server-migration/host-keys/taragarmr/etc/ssh/ (its age recipient
# is &host_taragarmr in .sops.yaml); inject it with
#   nixos-anywhere ... --extra-files ~/server-migration/host-keys/taragarmr
# so secrets/taragarmr.yaml decrypts on first boot. Do not run scripts/bootstrap-sops.sh.
# krane's password is not in the repo or sops; set it on site: add --no-reboot to the
# nixos-anywhere call above (same command, same --extra-files), then
#   ssh root@<installer-ip> nixos-enter --root /mnt -c 'passwd krane'    (interactive)
# and reboot the installer. Without it sudo is unusable and deploys fail. Later deploys:
#   nixos-rebuild switch --flake .#taragarmr --target-host krane@taragarmr --sudo --ask-sudo-password
#
# Secrets (secrets/taragarmr.yaml): wireguard/{wg0,wg1}-private-key, couchdb/env,
# restic/{rest-env,repo-password}. A missing section switches that feature off.
{ ... }:
{
  imports = [
    ./hardware-configuration.nix
    ./disko.nix
    ./caddy.nix
    ./couchdb.nix
    ./spt.nix
    ./services.nix
    ./backup.nix
  ];

  system.stateVersion = "26.05";

  boot.loader.systemd-boot = {
    enable = true;
    # The ESP holds every generation's kernel and initrd.
    configurationLimit = 10;
  };
  boot.loader.efi.canTouchEfiVariables = true;

  # Firewall (explicit): ssh (server module), wg0 UDP 13231 + wg1 UDP 51821 and wg0 trusted
  # (wireguard module), 80/443 tcp and 443 udp for Caddy and 4242 from the LAN (caddy.nix),
  # the SPT/Fika ports on wg1 only (spt.nix).
}
