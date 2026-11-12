# The home LAN (Fritzbox, 192.168.178.0/24): router and the DHCP leases pinned there for the
# servers. Literal addresses elsewhere in hosts/ and modules/ read from here. wg0/wg1
# addresses live in lib/wireguard.nix.
{
  network = "192.168.178.0/24";
  router = "192.168.178.1";
  hosts = {
    taronychus = "192.168.178.22";
    taragarmr = "192.168.178.23";
    tarronax = "192.168.178.24";
    # Set up at home before it goes offsite.
    tarritator = "192.168.178.25";
  };
}
