{ lib, ... }:
{
  networking.useNetworkd = true;
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
    # MAC identifier so the Fritzbox's pinned leases keep matching.
    dhcpV4Config.ClientIdentifier = "mac";
    ipv6AcceptRAConfig.UseDNS = false;
    dhcpV6Config.UseDNS = false;
  };

  services.resolved.enable = true;
}
