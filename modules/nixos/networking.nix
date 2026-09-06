# Network stack: NetworkManager, firewall, mDNS, KDE Connect, wg0 template.
{
  config,
  lib,
  hostName,
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

  # TEMPLATE: gated on the secrets file existing, so `nix flake check` passes before it exists.
  # Fill in real values once it does.
  networking.wg-quick.interfaces.wg0 = lib.mkIf (builtins.pathExists ../../secrets/${hostName}.yaml) {
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
