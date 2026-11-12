# Docker as the container runtime for the services, also behind virtualisation.oci-containers.
{ config, ... }:
{
  virtualisation.docker = {
    enable = true;
    daemon.settings = {
      # User-defined networks (compose projects) are carved from 172.20.0.0/14 in /24s: 1024
      # networks. The default bridge docker0 stays on 172.17.0.0/16. Nothing here touches
      # 10.0.0.0/8 (the old host's pools), the LAN 192.168.178.0/24, wg0 192.168.82.0/24
      # or wg1 192.168.83.0/24.
      default-address-pools = [
        {
          base = "172.20.0.0/14";
          size = 24;
        }
      ];
      # Container logs rotate instead of growing without bound.
      log-driver = "local";
      log-opts = {
        max-size = "10m";
        max-file = "3";
      };
    };
    # Weekly: dangling images, stopped containers, unused networks. Not volumes, not unused
    # tagged images.
    autoPrune = {
      enable = true;
      dates = "weekly";
    };
  };

  virtualisation.oci-containers.backend = "docker";

  # The docker group is root-equivalent; the account already has sudo.
  users.users.${config.krane.user.name}.extraGroups = [ "docker" ];
}
