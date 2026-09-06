# Flatpak and the flathub remote only. Nothing is pre-installed: install
# via `flatpak install flathub <app-id>` on the running system.
{ pkgs, ... }:
{
  services.flatpak.enable = true;

  systemd.services.flatpak-add-flathub = {
    description = "Add the flathub flatpak remote";
    wantedBy = [ "multi-user.target" ];
    after = [
      "network-online.target"
      "flatpak-system-helper.service"
    ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.flatpak}/bin/flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo";
    };
  };
}
