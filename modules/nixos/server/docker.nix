{ config, ... }:
{
  virtualisation.docker = {
    enable = true;
    daemon.settings = {
      # Compose networks come from 172.20.0.0/14 in /24s (1024 networks). docker0 stays on
      # 172.17.0.0/16, clear of 10.0.0.0/8, the LAN 192.168.178.0/24, wg0 192.168.82.0/24 and
      # wg1 192.168.83.0/24.
      default-address-pools = [
        {
          base = "172.20.0.0/14";
          size = 24;
        }
      ];
      log-driver = "local";
      log-opts = {
        max-size = "10m";
        max-file = "3";
      };
    };
    autoPrune = {
      enable = true;
      dates = "weekly";
    };
  };

  virtualisation.oci-containers.backend = "docker";

  # The docker group is root-equivalent; the account already has sudo.
  users.users.${config.krane.user.name}.extraGroups = [ "docker" ];
}
