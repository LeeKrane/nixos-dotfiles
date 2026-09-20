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

  # TEMPLATE: gated on the wireguard secrets section being present, so `nix flake check`
  # passes before it exists and hosts that never fill it in (no `wireguard:` section in
  # secrets/<host>.yaml) don't get a wg0 interface with no key to point at.
  # Fill in real values once it does.
  # Reads config.sops.secrets: keep sops.secrets gated on file contents only, never on config.networking.*, or this recurses.
  networking.wg-quick.interfaces.wg0 = lib.mkIf (config.sops.secrets ? "wireguard/wg0-private-key") {
    # address = [ "10.0.0.X/24" ]; # CHANGE-ME: this host's tunnel address
    autostart = false; # flipped to true once the secrets file is real
    privateKeyFile = config.sops.secrets."wireguard/wg0-private-key".path;
    # No default `publicKey`, so leave `peers` unset until real values exist.
    # peers = [
    #   {
    #     publicKey = "CHANGE-ME"; # peer's WireGuard public key
    #     endpoint = "CHANGE-ME:51820"; # peer host:port
    #     allowedIPs = [ "10.0.0.0/24" ]; # CHANGE-ME: real tunnel subnet
    #   }
    # ];
  };
}
