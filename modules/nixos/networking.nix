# Network stack: NetworkManager, firewall, mDNS, KDE Connect, wg0 template.
{
  config,
  lib,
  ...
}:
{
  networking.networkmanager.enable = true;
  networking.firewall.enable = true;

  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = {
      enable = true;
      addresses = true;
      workstation = true;
    };
  };

  # Opens its own firewall range. No manual firewall rules needed.
  programs.kdeconnect.enable = true;

  # Tunnel values (address, peer identity, endpoint, keys) live encrypted in
  # secrets/<host>.yaml's wireguard section, never in this file. sops.nix
  # renders them into a wg0.conf template consumed here as configFile, so
  # nothing but the fixed keepalive is cleartext.
  # Gated on the template existing: hosts with no `wireguard:` section in
  # secrets/<host>.yaml get no template and no wg0 interface.
  # Reads config.sops.templates: keep sops.secrets/templates gated on file
  # contents only, never on config.networking.*, or this recurses.
  networking.wg-quick.interfaces.wg0 = lib.mkIf (config.sops.templates ? "wg0.conf") {
    configFile = config.sops.templates."wg0.conf".path;
    autostart = true;
  };

  # WireGuard peer name for the tunnel server; only meaningful when wg0 is up.
  networking.hosts = lib.mkIf (config.sops.templates ? "wg0.conf") {
    "192.168.82.1" = [ "taragarmr" ];
  };
}
