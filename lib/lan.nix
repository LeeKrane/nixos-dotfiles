# The home LAN (Fritzbox, 192.168.178.0/24): router and the DHCP leases pinned there for the
# servers. Literal addresses elsewhere in hosts/ and modules/ read from here. wg0/wg1
# addresses live in lib/wireguard.nix.
{
  network = "192.168.178.0/24";
  router = "192.168.178.1";
  hosts = {
    taronychus = "192.168.178.22";
    taragarmr = "192.168.178.23";
    tarritator = "192.168.178.25";
  };

  # The second LAN (tariognatha and tarronax; also 192.168.178.0/24, tarronax on DHCP there).
  # tariognatha's USB network adapter wakes it from suspend; tarronax sends the magic packet.
  wol.tariognatha = {
    mac = "00:e0:4c:6c:58:e5";
    broadcast = "192.168.178.255";
  };
}
