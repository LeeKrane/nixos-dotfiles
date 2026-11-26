# The home LAN (Fritzbox, 192.168.178.0/24): router and the DHCP leases pinned for the servers.
{
  network = "192.168.178.0/24";
  router = "192.168.178.1";
  hosts = {
    taronychus = "192.168.178.22";
    taragarmr = "192.168.178.23";
    tarritator = "192.168.178.25";
  };

  wol.tariognatha = {
    mac = "00:e0:4c:6c:58:e5";
    broadcast = "192.168.178.255";
  };
}
