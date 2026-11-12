# Server network baseline: systemd-networkd + systemd-resolved, DHCP on wired ethernet.
# Per-host static addressing or extra interfaces (wg0, bridges) are added in the host's module.
{ lib, ... }:
{
  networking.useNetworkd = true;
  # The scripted dhcpcd path stays off; networkd owns addressing below.
  networking.useDHCP = lib.mkDefault false;
  networking.firewall.enable = true;

  systemd.network.enable = true;
  # Name globs, not only Type=ether: veth pairs and VM taps are also Type=ether and must not
  # get DHCP. Docker and libvirt bridges have a different type and a different name.
  systemd.network.networks."10-wired" = {
    matchConfig = {
      Type = "ether";
      Name = "en* eth*";
    };
    networkConfig.DHCP = "yes";
  };

  services.resolved.enable = true;
}
