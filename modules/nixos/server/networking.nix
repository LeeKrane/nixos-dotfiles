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
    # Identify by MAC like the old OSes did, so the Fritzbox's pinned leases keep matching.
    dhcpV4Config.ClientIdentifier = "mac";
    # DNS from DHCPv4 only (the Fritzbox's 192.168.178.1). Its IPv6 DNS address, learned from
    # router advertisements and DHCPv6, did not answer on taragarmr (2026-11-14), and resolved
    # preferred it. IPv6 addressing stays on.
    ipv6AcceptRAConfig.UseDNS = false;
    dhcpV6Config.UseDNS = false;
  };

  services.resolved.enable = true;
}
